# frozen_string_literal: true

require "rails_helper"

RSpec.describe Persona::VerificationPipelineJob do
  let(:identity) do
    create(:identity,
      first_name: "Heidi", last_name: "Trashworth",
      legal_first_name: nil, legal_last_name: nil,
      birthday: Date.parse("2008-06-15"), country: :US)
  end

  let(:persona_record) do
    create(:identity_persona_record,
      identity: identity,
      name_first: "HEIDI",
      name_last: "TRASHWORTH",
      birthdate: Date.parse("2008-06-15"),
      country_code: "US",
      expiration_date: 3.years.from_now.to_date,
      entity_confidence_score: 0.98,
      checks: [
        { "name" => "id_entity_detection", "status" => "passed", "reasons" => [], "requirement" => "required" }
      ])
  end

  let(:doc) { create(:identity_document, identity: identity) }

  let(:verification) do
    create(:persona_verification,
      identity: identity,
      persona_record: persona_record,
      identity_document: doc,
      status: :pending)
  end

  def perform
    described_class.perform_now(verification)
  end

  context "clean verification" do
    it "auto-approves" do
      perform
      expect(verification.reload).to be_approved
    end

    it "produces no issues" do
      perform
      expect(verification.reload.issues).to be_blank
    end
  end

  context "with resemblances" do
    let(:other_identity) { create(:identity, first_name: "Someone", last_name: "Else") }

    before do
      Identity::Resemblance.create!(identity: identity, past_identity: other_identity)
    end

    it "holds for manual review" do
      perform
      expect(verification.reload).to be_pending
    end

    it "records resemblance issue" do
      perform
      expect(verification.reload.issues).to include(a_string_matching(/resemblances/i))
    end
  end

  context "with tombstone collision" do
    before do
      deletion = Deletion.create!(email_hash: Deletion.hash_email("somebody@example.com"))
      Identity::TombstoneCollision.create!(identity: identity, deletion: deletion)
    end

    it "holds for manual review" do
      perform
      expect(verification.reload).to be_pending
    end

    it "records tombstone issue" do
      perform
      expect(verification.reload.issues).to include(a_string_matching(/previously deleted/i))
    end
  end

  context "under 13" do
    before do
      identity.update!(birthday: 10.years.ago.to_date)
      persona_record.update!(birthdate: 10.years.ago.to_date)
    end

    it "denies the verification" do
      perform
      expect(verification.reload).to be_rejected
    end
  end

  context "with sketchy behaviors" do
    before do
      persona_record.update!(behaviors: { "devtools_open" => true })
    end

    it "holds for manual review" do
      perform
      expect(verification.reload).to be_pending
    end

    it "records the behavior issue" do
      perform
      expect(verification.reload.issues).to include(a_string_matching(/devtools/i))
    end
  end

  context "with name mismatch on document" do
    before do
      persona_record.update!(name_first: "ZEPHYR", name_last: "MOONBEAM")
    end

    it "holds for manual review" do
      perform
      expect(verification.reload).to be_pending
    end
  end

  context "with multiple low signals that stack" do
    before do
      persona_record.update!(
        network_signals: { "is_vpn" => true, "is_proxy" => true },
        behaviors: {
          "bot_score" => 6,
          "completion_time" => 20,
          "hesitation_percentage" => 90
        }
      )
    end

    it "holds for manual review when low signals combine past threshold" do
      perform
      expect(verification.reload).to be_pending
    end
  end

  context "with low signals that don't reach threshold" do
    before do
      persona_record.update!(
        network_signals: { "is_vpn" => true, "is_datacenter" => true },
        behaviors: { "bot_score" => 6 }
      )
    end

    it "still approves" do
      perform
      expect(verification.reload).to be_approved
    end
  end
end
