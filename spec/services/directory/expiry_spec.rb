# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Expiry do
  include ActiveSupport::Testing::TimeHelpers

  describe ".parse" do
    it "reads a bare date as the end of that day anywhere on earth" do
      expect(described_class.parse("2027-03-01")).to eq(Time.utc(2027, 3, 2, 11, 59, 59.999999r))
    end

    it "takes an explicit datetime as given" do
      expect(described_class.parse("2027-03-01T12:30:00-05:00")).to eq(Time.utc(2027, 3, 1, 17, 30))
      expect(described_class.parse("2027-03-01 12:30Z")).to eq(Time.utc(2027, 3, 1, 12, 30))
    end

    it "refuses anything ambiguous or impossible" do
      %w[2027-02-30 tomorrow 1/2/2027 2027-03-01T25:00].each do |raw|
        expect(described_class.parse(raw)).to be_nil, raw
      end
    end

    it "keeps today's date valid for the rest of today, wherever you are" do
      travel_to Time.utc(2027, 3, 1, 23, 0) do
        expect(described_class.parse("2027-03-01")).to be > Time.current
        expect(described_class.first_selectable_date).to eq(Date.new(2027, 3, 1))
      end
    end
  end

  it "round-trips a date through storage and display" do
    membership_time = described_class.parse("2027-03-01").round(6)

    expect(described_class.date_for(membership_time)).to eq(Date.new(2027, 3, 1))
    expect(described_class.label(membership_time)).to eq("2027-03-01")
    expect(described_class.label(Time.utc(2027, 3, 1, 17, 30))).to eq("2027-03-01 17:30 UTC")
  end
end
