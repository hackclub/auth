# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletionService do
  describe ".check_for_email" do
    it "returns nil when no tombstone exists" do
      expect(described_class.check_for_email("nobody@example.com")).to be_nil
    end

    it "returns the deletion record when email is tombstoned" do
      deletion = Deletion.create!(email_hash: Deletion.hash_email("gone@example.com"))
      expect(described_class.check_for_email("gone@example.com")).to eq(deletion)
    end

    it "matches case-insensitively" do
      Deletion.create!(email_hash: Deletion.hash_email("gone@example.com"))
      expect(described_class.check_for_email("GONE@Example.COM")).to be_present
    end
  end

  describe ".check_for_name_combos" do
    let(:dob) { Date.new(2005, 6, 15) }

    it "returns empty when no tombstone matches" do
      expect(described_class.check_for_name_combos("Nobody Here", dob)).to be_empty
    end

    it "finds a matching tombstone by name overlap" do
      hashes = Deletion.name_combo_hashes("John Michael Smith", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("John Smith", dob)
      expect(results).to include(deletion)
    end

    it "does not match when DOB differs" do
      hashes = Deletion.name_combo_hashes("John Smith", dob)
      Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("John Smith", Date.new(2000, 1, 1))
      expect(results).to be_empty
    end

    it "matches regardless of token order" do
      hashes = Deletion.name_combo_hashes("John Smith", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("Smith John", dob)
      expect(results).to include(deletion)
    end

    it "collides on shared name pairs across different people" do
      hashes = Deletion.name_combo_hashes("Carlos Miguel Rivera", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("Miguel Rivera", dob)
      expect(results).to include(deletion)
    end

    it "matches through diacritics" do
      hashes = Deletion.name_combo_hashes("José García", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("Jose Garcia", dob)
      expect(results).to include(deletion)
    end
  end

  describe ".check_ip" do
    it "returns empty when no match" do
      expect(described_class.check_ip("192.168.1.1")).to be_empty
    end

    it "finds deletions containing the hashed IP" do
      deletion = Deletion.create!(
        email_hash: "abc123",
        session_ips: [ Deletion.hash_ip("10.0.0.1"), Deletion.hash_ip("10.0.0.2") ]
      )

      expect(described_class.check_ip("10.0.0.1")).to include(deletion)
    end
  end

  describe ".execute_deletion" do
    let(:identity) { create(:identity) }

    it "raises when identity is already tombstoned" do
      identity.update_columns(primary_email: "tombstoned+1@identity.invalid")
      expect {
        described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD")
      }.to raise_error(DeletionService::Error, /already tombstoned/)
    end

    it "raises when identity has a backend_user" do
      create(:backend_user, identity: identity)
      expect {
        described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD")
      }.to raise_error(DeletionService::Error, /backend_user/)
    end

    it "scrubs PII and creates tombstone record" do
      original_email = identity.primary_email

      described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD", logger: ->(_) { })

      identity.reload
      expect(identity.first_name).to eq("[REDACTED]")
      expect(identity.primary_email).to end_with("@identity.invalid")
      expect(identity.permabanned).to be true
      expect(Deletion.find_by(email_hash: Deletion.hash_email(original_email))).to be_present
    end

    it "logs a deletion_request activity" do
      expect {
        described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD", logger: ->(_) { })
      }.to change { PublicActivity::Activity.where(key: "identity.deletion_request").count }.by(1)
    end

    it "purges verification case document files" do
      kase = create(:verification_case, identity: identity)
      doc = create(:verification_case_document, verification_case: kase)
      blob_id = doc.file.blob.id

      described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD", logger: ->(_) { })

      expect(ActiveStorage::Attachment.where(blob_id: blob_id)).to be_empty
    end

    context "with a decided manual verification case" do
      let(:reviewer) { create(:backend_user) }
      let(:verification) { create(:manual_verification_call, :approved, identity: identity, reviewer: reviewer, sample_notes: "qa: saw the same doc") }
      let!(:kase) do
        create(:verification_case, :call_held, identity: identity, verification: verification, status: :approved,
          alternative_reason_details: "lost my passport moving house",
          persona_inquiry_id: "inq_fictional123",
          persona_session_token: "sess_fictional",
          submitted_fields: { "legal_name" => "Zephyrine Quokkason", "date_of_birth" => "2008-02-29",
                              "document_type" => "passport", "issuing_authority" => "Narnia" },
          persona_signal_snapshot: { "inquiry" => { "name-first" => "Zephyrine", "ip" => "203.0.113.9" } })
      end
      let!(:docs) do
        [
          create(:verification_case_document, verification_case: kase, document_kind: "persona_capture", source: "persona"),
          build(:verification_case_document, :call_screenshot, verification_case: kase).tap do |doc|
            doc.file.attach(io: StringIO.new("fake png"), filename: "call.png", content_type: "image/png")
            doc.save!
          end
        ]
      end
      let!(:comment) { kase.comments.create!(author: reviewer, body: "mum confirmed the address") }
      let!(:events) do
        [
          kase.events.create!(key: "case_opened", actor: reviewer, ip_address: "203.0.113.1", user_agent: "Mozilla/5.0 (staff)",
            data: { "skip_persona" => false }),
          kase.events.create!(key: "redo_requested", actor: reviewer, ip_address: "203.0.113.1", user_agent: "Mozilla/5.0 (staff)",
            data: { "message" => "retake the photo of your id card", "previous_inquiry_id" => "inq_old" }),
          kase.events.create!(key: "decision_approve", actor: reviewer, ip_address: "203.0.113.1", user_agent: "Mozilla/5.0 (staff)",
            data: { "verification_id" => verification.id, "checklist" => verification.checklist })
        ]
      end
      let!(:version_count_before) { PaperTrail::Version.where(item_type: "VerificationCase", item_id: kase.id).count }

      before do
        allow(Persona.instance).to receive(:redact_account)
        described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD", logger: ->(_) { })
      end

      it "blanks the case's identity fields but keeps the row and its outcome" do
        kase.reload
        expect(kase).to be_approved
        expect(kase.submitted_fields).to eq({})
        expect(kase.persona_signal_snapshot).to be_nil
        expect(kase.alternative_reason_details).to be_nil
        expect(kase.persona_inquiry_id).to be_nil
        expect(kase.persona_session_token).to be_nil
        expect(kase.access_token).to be_nil
        expect(kase.verification_id).to eq(verification.id)
      end

      it "keeps the event rows and kinds but drops ip, user agent and typed text" do
        rows = VerificationCase::Event.where(verification_case_id: kase.id).order(:id)
        expect(rows.map(&:key)).to eq(%w[case_opened redo_requested decision_approve])
        expect(rows.map(&:ip_address).uniq).to eq([ nil ])
        expect(rows.map(&:user_agent).uniq).to eq([ nil ])
        expect(rows.map(&:actor_id).uniq).to eq([ reviewer.id ])

        opened, redo_event, decision = rows.to_a
        expect(opened.data).to eq({ "skip_persona" => false })
        expect(redo_event.data).to eq({ "message" => "[REDACTED]", "previous_inquiry_id" => "inq_old" })
        expect(decision.data["verification_id"]).to eq(verification.id)
        expect(decision.data.dig("checklist", "notes")).to eq("[REDACTED]")
        expect(decision.data.dig("checklist", "doc_unaltered")).to be true
      end

      it "redacts comment bodies in place" do
        expect(comment.reload.body).to eq("[REDACTED]")
        expect(comment.author_id).to eq(reviewer.id)
      end

      it "drops the reviewer notes but keeps the checklist answers and confidence" do
        verification.reload
        expect(verification).to be_approved
        expect(verification.checklist).not_to have_key("notes")
        expect(verification.checklist["confidence"]).to eq("high")
        expect(verification.checklist_answer("doc_matches_live_face")).to be true
        expect(verification.sample_notes).to be_nil
        expect(verification.reviewer_id).to eq(reviewer.id)
      end

      it "purges the persona capture and staff screenshot blobs" do
        blob_ids = docs.map { |d| d.file.blob.id }
        expect(ActiveStorage::Attachment.where(blob_id: blob_ids)).to be_empty
        expect(ActiveStorage::Blob.where(id: blob_ids)).to be_empty
        expect(VerificationCase::Document.with_deleted.where(verification_case_id: kase.id).count).to eq(2)
      end

      it "deletes the case's PaperTrail versions" do
        expect(version_count_before).to be > 0
        expect(PaperTrail::Version.where(item_type: "VerificationCase", item_id: kase.id)).to be_empty
      end
    end
  end
end
