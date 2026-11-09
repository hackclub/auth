# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Person do
  let(:admin) { create(:identity) }

  describe ".search" do
    let!(:jane) { described_class.create!(identity: create(:identity, first_name: "Jane", last_name: "Doe"), created_by_identity_id: admin.id) }
    let!(:jim) { described_class.create!(identity: create(:identity, first_name: "Jim", last_name: "Doe"), created_by_identity_id: admin.id) }

    it "matches 'First Last'" do
      expect(described_class.search("Jane Doe")).to contain_exactly(jane)
    end

    it "still matches a single name" do
      expect(described_class.search("Doe")).to contain_exactly(jane, jim)
    end

    it "matches a last name with a space in it" do
      jim.identity.update_columns(last_name: "van Doe")
      expect(described_class.search("Jim van Doe")).to contain_exactly(jim)
    end
  end

  describe ".find_or_create_for_identity!" do
    let(:identity) { create(:identity) }

    it "returns the existing person after losing the insert race inside a transaction" do
      existing = described_class.create!(identity: identity, created_by_identity_id: admin.id)
      # simulate the race: the pre-check and the uniqueness validation both miss the
      # other writer's row, so the insert hits the unique index
      allow(described_class).to receive(:create!) { |**attrs| described_class.new(**attrs).tap { |p| p.save!(validate: false) } }
      allow(described_class).to receive(:find_by).and_call_original
      allow(described_class).to receive(:find_by).with(identity: identity).and_return(nil)
      allow(described_class).to receive(:find_by!).and_call_original

      result = nil
      ActiveRecord::Base.transaction do
        result = described_class.find_or_create_for_identity!(identity, created_by: admin)
        # the outer transaction is still usable
        expect(described_class.where(identity: identity).count).to eq(1)
      end
      expect(result).to eq(existing)
    end
  end
end
