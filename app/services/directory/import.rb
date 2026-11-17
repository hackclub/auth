# frozen_string_literal: true

require "csv"

module Directory
  # takes the advisory lock itself (not via mutate!) so Rebuild.call can skip it
  class Import
    Result = Struct.new(:valid?, :changes, :errors, :created_count, :skipped_count, keyword_init: true)

    # upload, pasted text, and the preview's re-post alike
    MAX_CSV_BYTES = 2.megabytes

    def self.call(csv_string:, dry_run: false, created_by:, skip_effective_members: false)
      new(csv_string:, dry_run:, created_by:, skip_effective_members:).call
    end

    def initialize(csv_string:, dry_run:, created_by:, skip_effective_members: false)
      @csv_string = csv_string
      @dry_run = dry_run
      @created_by = created_by
      @skip_effective_members = skip_effective_members
    end

    def call
      parse_rows
      resolve_rows

      if @dry_run
        Result.new(valid?: @errors.empty?, changes: @changes, errors: @errors,
                   created_count: @changes.count { |c| c[:action] == "add" },
                   skipped_count: @changes.count { |c| c[:action] != "add" })
      else
        persist
      end
    end

    private

    def parse_rows
      @rows = []
      @errors = []
      @changes = []

      if @csv_string.bytesize > MAX_CSV_BYTES
        @errors << { message: "CSV is too large (#{MAX_CSV_BYTES / 1.megabyte}MB max)" }
        return
      end

      # Excel's "CSV UTF-8" export starts with a BOM, which would glue itself to "email"
      # and hide the header row.
      csv = @csv_string.dup.force_encoding("UTF-8").scrub.delete_prefix("\uFEFF")
      lines = begin
        CSV.parse(csv, liberal_parsing: true)
      rescue CSV::MalformedCSVError => e
        @errors << { message: "couldn't parse CSV: #{e.message}" }
        return
      end
      return if lines.empty?

      first = lines.first
      if first.length >= 2 && first[0]&.strip&.downcase == "email"
        lines = lines.drop(1)
      end

      lines.each_with_index do |cols, idx|
        next if cols.all? { |c| c.nil? || c.strip.empty? }

        email = cols[0].to_s.strip
        email = email.downcase unless email.match?(/\A(ident|dper)!/) # preserve case-sensitive public IDs
        slug = cols[1]&.strip
        expires_at_raw = cols[2]&.strip.presence

        if email.blank?
          @errors << { row: idx + 1, message: "missing email" }
          next
        end
        if slug.blank?
          @errors << { row: idx + 1, message: "missing collection slug" }
          next
        end

        expires_at = nil
        if expires_at_raw
          expires_at = Directory::Expiry.parse(expires_at_raw)
          if expires_at.nil?
            @errors << { row: idx + 1, email:, message: "invalid expires_at: #{expires_at_raw} (use YYYY-MM-DD or an ISO 8601 datetime)" }
            next
          end
          # Membership validates this too, but on apply that's a RecordInvalid mid-import, after
          # a dry run that looked clean. Checking it here makes it a row error in both.
          if expires_at <= Time.current
            @errors << { row: idx + 1, email:, message: "expires_at must be in the future: #{expires_at_raw}" }
            next
          end
        end

        @rows << { email:, slug:, expires_at:, row_num: idx + 1 }
      end
    end

    def resolve_rows
      is_public_id = ->(v) { v.start_with?("ident!", "dper!") }
      emails = @rows.reject { |r| is_public_id.call(r[:email]) }.map { |r| r[:email] }.uniq
      person_pids = @rows.select { |r| is_public_id.call(r[:email]) }.map { |r| r[:email] }.uniq
      slugs = @rows.reject { |r| r[:slug].start_with?("dcol!") }.map { |r| r[:slug] }.uniq
      dcol_ids = @rows.select { |r| r[:slug].start_with?("dcol!") }.map { |r| r[:slug] }.uniq

      identities_by_email = Identity.where("lower(primary_email) IN (?)", emails).index_by { |i| i.primary_email.downcase }
      person_pids.each do |pid|
        if pid.start_with?("dper!")
          person = Directory::Person.find_by_public_id(pid)
          identities_by_email[pid] = person.identity if person
        else
          identity = Identity.find_by_public_id(pid)
          identities_by_email[pid] = identity if identity
        end
      end

      collections_by_slug = Directory::Collection.where(slug: slugs).index_by(&:slug)
      dcol_ids.each do |pid|
        col = Directory::Collection.find_by_public_id(pid)
        collections_by_slug[pid] = col if col
      end

      @resolved = []

      @rows.each do |row|
        identity = identities_by_email[row[:email]]
        collection = collections_by_slug[row[:slug]]

        unless identity
          @errors << { row: row[:row_num], email: row[:email], message: "identity not found" }
          next
        end
        unless collection
          @errors << { row: row[:row_num], email: row[:email], message: "collection not found: #{row[:slug]}" }
          next
        end

        @resolved << { identity:, collection:, expires_at: row[:expires_at], email: row[:email], row_num: row[:row_num] }
      end

      identity_ids = @resolved.map { |e| e[:identity].id }.uniq
      persons_by_identity = Directory::Person.where(identity_id: identity_ids).index_by(&:identity_id)

      person_ids = persons_by_identity.values.map(&:id)
      collection_ids = @resolved.map { |e| e[:collection].id }.uniq
      active_pairs = if person_ids.any? && collection_ids.any?
        Directory::Membership.active
          .where(collection_id: collection_ids, member_person_id: person_ids)
          .pluck(:collection_id, :member_person_id)
          .to_set
      else
        Set.new
      end

      # "skip people who already have access via an alternate path": check
      # effective_memberships (which include indirect access through nested groups)
      # rather than just direct membership on the target collection
      effective_pairs = if @skip_effective_members && person_ids.any? && collection_ids.any?
        Directory::EffectiveMembership
          .where(collection_id: collection_ids, person_id: person_ids)
          .pluck(:collection_id, :person_id)
          .to_set
      else
        Set.new
      end

      first_row = {}
      @resolved.each do |entry|
        # The same person and collection twice (exact repeat, different case, email and
        # ident! for one person, slug and dcol! for one collection): first row wins.
        key = [ entry[:identity].id, entry[:collection].id ]
        if first_row.key?(key)
          @changes << { email: entry[:email], collection: entry[:collection].slug, expires_at: entry[:expires_at], action: "skip_duplicate", duplicate_of: first_row[key] }
          entry[:duplicate] = true
          next
        end
        first_row[key] = entry[:row_num]

        person = persons_by_identity[entry[:identity].id]
        existing = person ? active_pairs.include?([ entry[:collection].id, person.id ]) : false
        effective = !existing && person ? effective_pairs.include?([ entry[:collection].id, person.id ]) : false

        if existing
          @changes << { email: entry[:email], collection: entry[:collection].slug, expires_at: entry[:expires_at], action: "skip_existing" }
        elsif effective
          @changes << { email: entry[:email], collection: entry[:collection].slug, expires_at: entry[:expires_at], action: "skip_effective" }
        else
          @changes << { email: entry[:email], collection: entry[:collection].slug, expires_at: entry[:expires_at], action: "add" }
        end

        entry[:existing] = existing || effective
        entry[:person] = person
      end
    end

    def persist
      created_count = 0
      skipped_count = 0

      ActiveRecord::Base.transaction do
        if @errors.any?
          return Result.new(valid?: false, changes: @changes, errors: @errors,
                           created_count: 0, skipped_count: 0)
        end

        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{Directory::Rebuild::LOCK_KEY})")

        @resolved.each do |entry|
          if entry[:existing] || entry[:duplicate]
            skipped_count += 1
            next
          end

          person = entry[:person] || find_or_create_person!(entry[:identity])

          # Savepoint, so a unique violation only rolls back this row rather than
          # aborting the whole import transaction.
          ActiveRecord::Base.transaction(requires_new: true) do
            Directory::Membership.purge_expired!(Directory::Membership.where(collection: entry[:collection], member_person: person))

            Directory::Membership.create!(
              collection: entry[:collection],
              member_person: person,
              expires_at: entry[:expires_at],
              created_by_identity_id: @created_by.id
            )
          end

          created_count += 1
        rescue ActiveRecord::RecordNotUnique
          skipped_count += 1
        end

        Directory::Rebuild.call(cause: Directory.cause("import", actor: @created_by.id), skip_lock: true) if created_count > 0
      end

      Result.new(valid?: true, changes: @changes, errors: @errors,
                 created_count:, skipped_count:)
    end

    def find_or_create_person!(identity)
      Directory::Person.find_or_create_for_identity!(identity, created_by: @created_by)
    end
  end
end
