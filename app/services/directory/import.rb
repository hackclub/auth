# frozen_string_literal: true

require "csv"

module Directory
  # CSV bulk import: parses rows, resolves identities and collections, creates persons
  # and memberships, then triggers one rebuild. Supports dry_run mode for preview.
  # Takes the advisory lock itself (not via mutate!) so it can skip the lock in Rebuild.call.
  class Import
    Result = Struct.new(:valid?, :changes, :errors, :created_count, :skipped_count, keyword_init: true)

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

        email = cols[0]&.strip&.downcase
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
          begin
            expires_at = Time.zone.parse(expires_at_raw)
          rescue ArgumentError
            @errors << { row: idx + 1, email:, message: "invalid expires_at: #{expires_at_raw}" }
            next
          end
        end

        @rows << { email:, slug:, expires_at:, row_num: idx + 1 }
      end
    end

    def resolve_rows
      # Batch-load identities and collections
      emails = @rows.map { |r| r[:email] }.uniq
      slugs = @rows.map { |r| r[:slug] }.uniq

      identities_by_email = Identity.where("lower(primary_email) IN (?)", emails).index_by { |i| i.primary_email.downcase }
      collections_by_slug = Directory::Collection.where(slug: slugs).index_by(&:slug)

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

      # Now check for duplicates and build changes
      @resolved.each do |entry|
        person = Directory::Person.find_by(identity: entry[:identity])
        existing = if person
          Directory::Membership.exists?(collection: entry[:collection], member_person: person)
        else
          false
        end

        if existing
          @changes << { email: entry[:email], collection: entry[:collection].slug, action: "skip_existing" }
        else
          @changes << { email: entry[:email], collection: entry[:collection].slug, action: "add" }
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

          person = entry[:person] || Directory::Person.find_or_create_by!(identity: entry[:identity]) do |p|
            p.created_by_identity_id = @created_by.id
          end

          Directory::Membership.create!(
            collection: entry[:collection],
            member_person: person,
            expires_at: entry[:expires_at],
            created_by_identity_id: @created_by.id
          )

          created_count += 1
        end

        Directory::Rebuild.call(cause: Directory.cause("import", actor: @created_by.id), skip_lock: true) if created_count > 0
      end

      Result.new(valid?: true, changes: @changes, errors: @errors,
                 created_count:, skipped_count:)
    end
  end
end
