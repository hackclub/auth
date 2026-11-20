# frozen_string_literal: true

require "rails_helper"

RSpec.describe SafeCsv do
  describe ".escape" do
    [
      "=1+1", "+1+1", "-1+1", "@SUM(1+1)", "\t=1+1", "\r=1+1", "\tplain", "\rplain", " =1+1", "\n-1+1",
      %(=HYPERLINK("http://evil","x"))
    ].each do |payload|
      it "prefixes a quote to #{payload.inspect}" do
        expect(described_class.escape(payload)).to eq("'#{payload}")
      end
    end

    [ "Heidi Trashworth", "Mary-Jane O'Neil", "jane+tag@example.com", "a=b", " Heidi", "'already quoted", "" ].each do |value|
      it "leaves #{value.inspect} alone" do
        expect(described_class.escape(value)).to eq(value)
      end
    end

    it "leaves nil and numbers alone" do
      expect(described_class.escape(nil)).to be_nil
      expect(described_class.escape(-5)).to eq(-5)
      expect(described_class.escape(1.5)).to eq(1.5)
    end

    it "checks what non-strings will be written as" do
      expect(described_class.escape(:"=1+1")).to eq("'=1+1")
    end
  end

  describe ".generate_line" do
    it "escapes each cell, then quotes like CSV.generate_line" do
      line = described_class.generate_line([ %(=HYPERLINK("http://evil","x")), "Mary-Jane", nil, 3 ])

      expect(line).to eq(%("'=HYPERLINK(""http://evil"",""x"")",Mary-Jane,,3\n))
      expect(CSV.parse_line(line)).to eq([ %('=HYPERLINK("http://evil","x")), "Mary-Jane", nil, "3" ])
    end

    it "passes options through to CSV" do
      expect(described_class.generate_line([ "a", "-b" ], col_sep: ";")).to eq("a;'-b\n")
    end
  end
end
