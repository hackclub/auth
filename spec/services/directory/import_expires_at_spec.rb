# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Import, "expires_at" do
  let(:admin) { create(:identity) }
  let(:member) { create(:identity) }
  let!(:group) { create(:directory_group, slug: "temps") }

  def import(expires_at, dry_run: false)
    Directory::Import.call(csv_string: "#{member.primary_email},temps,#{expires_at}\n", dry_run:, created_by: admin)
  end

  def memberships
    Directory::Membership.where(collection: group)
  end

  describe "a value that isn't an unambiguous date" do
    {
      "tomorrow" => "Time.zone.parse returns nil",
      "next friday" => "Time.zone.parse returns today's midnight",
      "1/2/2027" => "day-first or month-first",
      "2027-02-30" => "Time.zone.parse rolls it over to March 2",
      "2027-13-45" => "Time.zone.parse raises",
      "2027-01-01 lol" => "Time.zone.parse ignores the trailing junk",
      "2027-01-01T25:00" => "hour out of range",
      "2099-01-01T12:00+25:00" => "Time.zone.iso8601 drops the bogus offset and reads it as UTC"
    }.each do |raw, why|
      it "rejects #{raw.inspect} (#{why}) as a row error and creates nothing" do
        result = import(raw)

        expect(result).not_to be_valid
        expect(result.errors).to contain_exactly(
          a_hash_including(row: 1, email: member.primary_email, message: a_string_including("invalid expires_at"))
        )
        expect(memberships).to be_empty
      end
    end

    it "is reported by the dry run, so the preview can't offer to apply it" do
      result = import("tomorrow", dry_run: true)

      expect(result).not_to be_valid
      expect(result.errors.sole[:message]).to include("invalid expires_at: tomorrow")
      expect(result.changes).to be_empty
    end

    it "fails the whole import, not just its own row" do
      other = create(:identity)
      csv = "#{other.primary_email},temps,\n#{member.primary_email},temps,next friday\n"

      result = Directory::Import.call(csv_string: csv, dry_run: false, created_by: admin)

      expect(result).not_to be_valid
      expect(result.errors.sole).to include(row: 2)
      expect(memberships).to be_empty
    end
  end

  describe "a value in the past" do
    # The membership model rejects these too (expires_at_in_future). Catching it per row keeps the
    # dry run honest instead of letting apply blow up on create! with RecordInvalid.
    it "is a row error in the dry run" do
      result = import("2020-01-01", dry_run: true)

      expect(result).not_to be_valid
      expect(result.errors.sole[:message]).to include("must be in the future")
    end

    it "is a row error on apply and creates nothing" do
      result = nil
      expect { result = import("2020-01-01") }.not_to raise_error

      expect(result).not_to be_valid
      expect(memberships).to be_empty
    end
  end

  describe "a valid value" do
    it "applies a date as midnight UTC" do
      result = import("2099-01-01")

      expect(result).to be_valid
      expect(memberships.sole.expires_at).to eq(Time.utc(2099, 1, 1))
    end

    it "applies a datetime, honoring its offset" do
      import("2099-01-01T12:30:00-05:00")

      expect(memberships.sole.expires_at).to eq(Time.utc(2099, 1, 1, 17, 30))
    end

    it "accepts a space instead of T, and a Z suffix" do
      import("2099-01-01 12:30Z")

      expect(memberships.sole.expires_at).to eq(Time.utc(2099, 1, 1, 12, 30))
    end

    it "carries the parsed expiry into the dry run's changes" do
      result = import("2099-01-01T12:30:00-05:00", dry_run: true)

      expect(result.changes.sole).to include(action: "add", expires_at: Time.utc(2099, 1, 1, 17, 30))
      expect(memberships).to be_empty
    end
  end

  describe "a blank value" do
    it "creates a membership that never expires, and says so in the changes" do
      preview = import("", dry_run: true)
      expect(preview.changes.sole).to include(expires_at: nil)

      import("")
      expect(memberships.sole.expires_at).to be_nil
    end
  end
end
