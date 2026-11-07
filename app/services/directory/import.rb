# frozen_string_literal: true

require "csv"

module Directory
  # CSV bulk import: parses rows, resolves identities and collections, creates persons
  # and memberships, then triggers one rebuild. Supports dry_run mode for preview.
  # Takes the advisory lock itself (not via mutate!) so it can skip the lock in Rebuild.call.
  class Import
    Result = Struct.new(:valid?, :changes, :errors, :created_count, :skipped_count, keyword_init: true)

    # YYYY-MM-DD, optionally followed by a time (after T or a space) and a Z or ±HH:MM offset.
    EXPIRES_AT_FORMAT = /\A(\d{4})-(\d{2})-(\d{2})(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-](?:[01]\d|2[0-3])(?::?[0-5]\d)?)?)?\z/i

    def self.call(csv_string:, dry_run: false, created_by:)
      new(csv_string:, dry_run:, created_by:).call
    end

    def initialize(csv_string:, dry_run:, created_by:)
      @csv_string = csv_string
      @dry_run = dry_run
      @created_by = created_by
    end

    def call
      parse_rows
      resolve_rows

      if @dry_run
        Result.new(valid?: @errors.empty?, changes: @changes, errors: @errors,
                   created_count: @changes.count { |c| c[:action] == "add" },
                   skipped_count: @changes.count { |c| c[:action] == "skip_existing" })
      else
        persist
      end
    end

    private

    def parse_rows
      @rows = []
      @errors = []
      @changes = []

      lines = CSV.parse(@csv_string, liberal_parsing: true)
      return if lines.empty?

      # Detect header row
      first = lines.first
      if first.length >= 2 && first[0]&.strip&.downcase == "email"
        lines = lines.drop(1)
      end

      lines.each_with_index do |cols, idx|
        next if cols.all? { |c| c.nil? || c.strip.empty? }

        email = cols[0]&.strip
        email = email.downcase unless email&.match?(/\A(ident|dper)!/) # preserve case-sensitive public IDs
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
          expires_at = parse_expires_at(expires_at_raw)
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

    # Strict on purpose, because Time.zone.parse guesses: nil for "tomorrow" (a membership that
    # never expires), today's midnight for "next friday", Feb 1 for "1/2/2027", and March 2 for
    # "2027-02-30". For an access expiry a wrong guess is worse than a row error, so anything but
    # unambiguous ISO 8601 returns nil. A bare date means midnight in Time.zone (UTC).
    def parse_expires_at(raw)
      date = EXPIRES_AT_FORMAT.match(raw)&.captures&.map(&:to_i)
      return unless date && Date.valid_date?(*date)

      Time.zone.iso8601(raw.sub(" ", "T"))
    rescue ArgumentError # out-of-range time, e.g. hour 25
      nil
    end

    def resolve_rows
      emails = @rows.reject { |r| r[:email].start_with?("ident!") }.map { |r| r[:email] }.uniq
      ident_ids = @rows.select { |r| r[:email].start_with?("ident!") }.map { |r| r[:email] }.uniq
      slugs = @rows.reject { |r| r[:slug].start_with?("dcol!") }.map { |r| r[:slug] }.uniq
      dcol_ids = @rows.select { |r| r[:slug].start_with?("dcol!") }.map { |r| r[:slug] }.uniq

      identities_by_email = Identity.where("lower(primary_email) IN (?)", emails).index_by { |i| i.primary_email.downcase }
      ident_ids.each do |pid|
        identity = Identity.find_by_public_id(pid)
        identities_by_email[pid] = identity if identity
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
          @errors << { row: row[:row_num], slug: row[:slug], message: "collection not found" }
          next
        end

        @resolved << { identity:, collection:, expires_at: row[:expires_at], email: row[:email] }
      end

      # Batch-load persons and active memberships to avoid N+1 queries
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

      @resolved.each do |entry|
        person = persons_by_identity[entry[:identity].id]
        existing = person ? active_pairs.include?([ entry[:collection].id, person.id ]) : false

        if existing
          @changes << { email: entry[:email], collection: entry[:collection].slug, expires_at: entry[:expires_at], action: "skip_existing" }
        else
          @changes << { email: entry[:email], collection: entry[:collection].slug, expires_at: entry[:expires_at], action: "add" }
        end

        entry[:existing] = existing
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
          if entry[:existing]
            skipped_count += 1
            next
          end

          person = entry[:person] || find_or_create_person!(entry[:identity])

          Directory::Membership.expired.where(collection: entry[:collection], member_person: person).delete_all

          Directory::Membership.create!(
            collection: entry[:collection],
            member_person: person,
            expires_at: entry[:expires_at],
            created_by_identity_id: @created_by.id
          )

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
      Directory::Person.find_or_create_by!(identity: identity) do |p|
        p.created_by_identity_id = @created_by.id
      end
    rescue ActiveRecord::RecordNotUnique
      Directory::Person.find_by!(identity: identity)
    end
  end
end
