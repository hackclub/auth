# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Import, "input robustness" do
  let(:admin) { create(:identity) }
  let!(:jane) { create(:identity, primary_email: "jane@example.com") }
  let!(:team) { create(:directory_group, slug: "team") }

  def import(csv, dry_run: false) = described_class.call(csv_string: csv, dry_run: dry_run, created_by: admin)

  def memberships = Directory::Membership.where(collection: team)

  describe "the same person and collection twice" do
    [
      [ "exact repeat", "jane@example.com,team\njane@example.com,team\n" ],
      [ "different case", "jane@example.com,team\nJANE@example.com,team\n" ],
      [ "email and ident!", ->(j, t) { "jane@example.com,team\n#{j.public_id},team\n" } ],
      [ "slug and dcol!", ->(j, t) { "jane@example.com,team\njane@example.com,#{t.public_id}\n" } ]
    ].each do |label, csv|
      it "previews and applies cleanly (#{label})" do
        csv = csv.call(jane, team) if csv.respond_to?(:call)

        preview = import(csv, dry_run: true)
        expect(preview).to be_valid
        expect(preview.changes.map { |c| c[:action] }).to eq(%w[add skip_duplicate])

        result = import(csv)
        expect(result).to be_valid
        expect(result.created_count).to eq(1)
        expect(result.skipped_count).to eq(1)
        expect(memberships.count).to eq(1)
      end
    end
  end

  it "reads an Excel 'CSV UTF-8' export (leading BOM) as having a header" do
    result = import("﻿email,collection_slug,expires_at\njane@example.com,team,\n")
    expect(result).to be_valid
    expect(result.created_count).to eq(1)
  end

  it "turns malformed CSV into a row error instead of raising" do
    result = import(%(jane@example.com,"team\n))
    expect(result).not_to be_valid
    expect(result.errors.first[:message]).to match(/couldn't parse CSV/)
    expect(memberships).to be_empty
  end

  it "refuses input over the size limit whichever way it arrives" do
    big = "jane@example.com,team\n" * ((described_class::MAX_CSV_BYTES / 22) + 1)
    result = import(big)
    expect(result).not_to be_valid
    expect(result.errors.first[:message]).to match(/too large/)
  end
end
