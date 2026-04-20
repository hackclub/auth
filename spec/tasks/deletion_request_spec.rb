# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "deletion_request rake task" do
  before(:all) do
    Rails.application.load_tasks
  end

  let(:identity) { create(:identity, :with_address) }
  let(:task) { Rake::Task["deletion_request"] }

  before do
    task.reenable
  end

  def run_task(identifier)
    ENV["DELETION_REQUEST_CONFIRM"] = "true"
    task.invoke(identifier)
  ensure
    ENV.delete("DELETION_REQUEST_CONFIRM")
  end

  describe "safety gate" do
    it "aborts without DELETION_REQUEST_CONFIRM" do
      ENV.delete("DELETION_REQUEST_CONFIRM")
      expect { task.invoke(identity.id.to_s) }.to raise_error(SystemExit)
    end
  end

  describe "backend_user guard" do
    it "aborts if identity has a backend_user" do
      Backend::User.create!(identity: identity)
      expect { run_task(identity.id.to_s) }.to raise_error(SystemExit)
    end
  end

  describe "identity lookup" do
    it "finds by numeric ID" do
      expect { run_task(identity.id.to_s) }.not_to raise_error
    end

    it "finds by email" do
      expect { run_task(identity.primary_email) }.not_to raise_error
    end

    it "aborts for nonexistent identity" do
      expect { run_task("nonexistent@nope.com") }.to raise_error(SystemExit)
    end
  end

  describe "idempotency" do
    it "exits cleanly when run twice" do
      run_task(identity.id.to_s)
      task.reenable
      expect { run_task(identity.id.to_s) }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(0)
      end
    end
  end

  describe "identity scrubbing" do
    before { run_task(identity.id.to_s) }

    let(:tombstoned) { Identity.with_deleted.find(identity.id) }

    it "redacts name fields" do
      expect(tombstoned.first_name).to eq("[REDACTED]")
      expect(tombstoned.last_name).to eq("[REDACTED]")
      expect(tombstoned.legal_first_name).to eq("[REDACTED]")
      expect(tombstoned.legal_last_name).to eq("[REDACTED]")
    end

    it "sets tombstone email" do
      expect(tombstoned.primary_email).to eq("tombstoned+#{identity.id}@identity.invalid")
    end

    it "sets epoch birthday" do
      expect(tombstoned.birthday).to eq(Date.new(1970, 1, 1))
    end

    it "clears phone number" do
      expect(tombstoned.phone_number).to be_nil
    end

    it "clears aadhaar fields" do
      expect(tombstoned.aadhaar_number_ciphertext).to be_nil
      expect(tombstoned.aadhaar_number_bidx).to be_nil
    end

    it "locks the account" do
      expect(tombstoned.locked?).to be true
    end

    it "permabans the account" do
      expect(tombstoned.permabanned).to be true
    end

    it "soft-deletes the account" do
      expect(tombstoned.deleted_at).to be_present
    end

    it "preserves country" do
      expect(tombstoned.country).to eq(identity.country)
    end

    it "preserves slack_id" do
      expect(tombstoned.slack_id).to eq(identity.slack_id)
    end
  end

  describe "address scrubbing" do
    before { run_task(identity.id.to_s) }

    it "redacts address PII" do
      address = identity.addresses.first
      expect(address.first_name).to eq("[REDACTED]")
      expect(address.last_name).to eq("[REDACTED]")
      expect(address.line_1).to eq("[REDACTED]")
      expect(address.line_2).to be_nil
      expect(address.city).to eq("[REDACTED]")
      expect(address.state).to eq("[REDACTED]")
      expect(address.postal_code).to eq("[REDACTED]")
      expect(address.phone_number).to eq("[REDACTED]")
    end

    it "preserves address country" do
      address = identity.addresses.first
      expect(address.country).to be_present
    end
  end

  describe "auth data destruction" do
    let!(:login_attempt) { LoginAttempt.create!(identity: identity, aasm_state: "incomplete") }

    before { run_task(identity.id.to_s) }

    it "destroys login attempts" do
      expect(LoginAttempt.where(identity_id: identity.id)).to be_empty
    end

    it "destroys sessions" do
      expect(IdentitySession.where(identity_id: identity.id)).to be_empty
    end
  end

  describe "document file purging" do
    before do
      ActiveRecord::Encryption.configure(
        primary_key: "test-primary-key-that-is-long-enough",
        deterministic_key: "test-deterministic-key-long-enough",
        key_derivation_salt: "test-key-derivation-salt-long-enough"
      )
    end

    let!(:document) do
      doc = Identity::Document.new(identity: identity, document_type: :government_id)
      doc.save!(validate: false)
      doc.files.attach(
        io: StringIO.new("fake image data"),
        filename: "my_passport.jpg",
        content_type: "image/jpeg"
      )
      doc
    end

    before { run_task(identity.id.to_s) }

    it "purges the blob records" do
      expect(document.files.reload).to be_empty
    end

    it "preserves the document record" do
      expect(Identity::Document.with_deleted.where(identity_id: identity.id).count).to eq(1)
    end
  end

  describe "verification preservation" do
    let!(:document) do
      doc = Identity::Document.new(identity: identity, document_type: :government_id)
      doc.save!(validate: false)
      doc
    end
    let!(:verification) do
      v = Verification::DocumentVerification.create!(identity: identity, identity_document: document)
      v.update_columns(status: "approved", approved_at: 1.day.ago, internal_rejection_comment: "looks like Jane Doe")
      v
    end

    before { run_task(identity.id.to_s) }

    it "preserves verification status" do
      expect(verification.reload.status).to eq("approved")
    end

    it "preserves approval timestamp" do
      expect(verification.reload.approved_at).to be_present
    end

    it "preserves internal rejection comments" do
      expect(verification.reload.internal_rejection_comment).to eq("looks like Jane Doe")
    end
  end

  describe "resemblance cleanup" do
    let(:other_identity) { create(:identity) }

    before do
      Identity::Resemblance::NameResemblance.create!(identity: identity, past_identity: other_identity)
      Identity::Resemblance::NameResemblance.create!(identity: other_identity, past_identity: identity)
      run_task(identity.id.to_s)
    end

    it "destroys resemblances in both directions" do
      expect(Identity::Resemblance.where(identity_id: identity.id)).to be_empty
      expect(Identity::Resemblance.where(past_identity_id: identity.id)).to be_empty
    end
  end

  describe "program association cleanup" do
    let!(:owned_app) { Program.create!(name: "My App", redirect_uri: "https://example.com/cb", scopes: "openid", owner_identity: identity) }

    before { run_task(identity.id.to_s) }

    it "nullifies owned app ownership" do
      expect(owned_app.reload.owner_identity_id).to be_nil
    end
  end

  describe "PaperTrail version cleanup" do
    before do
      identity.update!(first_name: "Changed")
      expect(PaperTrail::Version.where(item_type: "Identity", item_id: identity.id).count).to be > 0
      run_task(identity.id.to_s)
    end

    it "deletes all versions for the identity" do
      expect(PaperTrail::Version.where(item_type: "Identity", item_id: identity.id)).to be_empty
    end
  end

  describe "PublicActivity scrubbing" do
    before do
      identity.create_activity(:admin_update, parameters: { old_email: "secret@example.com" })
      identity.create_activity(:email_change_requested, parameters: { old_email: "a@b.com", new_email: "c@d.com" })
      identity.create_activity(:use_backup_code, parameters: { method: "totp" })
      run_task(identity.id.to_s)
    end

    it "scrubs parameters on unsafe activity keys" do
      admin_update = PublicActivity::Activity.find_by(trackable_type: "Identity", trackable_id: identity.id, key: "identity.admin_update")
      expect(admin_update.read_attribute_before_type_cast("parameters")).to be_nil
    end

    it "scrubs parameters on email change activities" do
      ecr = PublicActivity::Activity.find_by(trackable_type: "Identity", trackable_id: identity.id, key: "identity.email_change_requested")
      expect(ecr.read_attribute_before_type_cast("parameters")).to be_nil
    end

    it "preserves parameters on safelisted activity keys" do
      backup = PublicActivity::Activity.find_by(trackable_type: "Identity", trackable_id: identity.id, key: "identity.use_backup_code")
      expect(backup.parameters).to be_present
    end

    it "preserves the activity records themselves" do
      expect(PublicActivity::Activity.where(trackable_type: "Identity", trackable_id: identity.id).count).to be >= 3
    end
  end

  describe "email tombstoning" do
    let(:original_email) { identity.primary_email }

    before { run_task(identity.id.to_s) }

    it "tombstones the original email" do
      expect(TombstonedEmail.tombstoned?(original_email)).to be true
    end

    it "blocks new identity creation with that email" do
      new_identity = build(:identity, primary_email: original_email)
      expect(new_identity).not_to be_valid
    end
  end

  describe "deletion request activity log" do
    before { run_task(identity.id.to_s) }

    it "logs a deletion_request activity" do
      activity = PublicActivity::Activity.find_by(
        trackable_type: "Identity",
        trackable_id: identity.id,
        key: "identity.deletion_request"
      )
      expect(activity).to be_present
      expect(activity.parameters[:tombstoned_at]).to be_present
    end
  end
end
