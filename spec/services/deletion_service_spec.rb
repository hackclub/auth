# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletionService do
  include ActiveSupport::Testing::TimeHelpers

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
  describe ".execute_deletion directory cleanup" do
    let(:admin) { create(:identity) }
    let(:victim) { create(:identity, first_name: "Zelda", last_name: "Quixote") }
    let(:group) { create(:directory_group, slug: "pii-probe", name: "PII Probe") }

    def delete!(identity) = described_class.execute_deletion(identity.reload, privacy_request_reference: "rec", logger: ->(_) { })

    it "leaves no activity row holding the deleted person's name or email" do
      email = victim.primary_email
      person = Directory::Person.create!(identity: victim, created_by_identity_id: admin.id)
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: group, member_person: person, created_by_identity_id: admin.id)
      end
      # a lookup miss from before they had an account
      group.create_activity :email_lookup_miss, owner: admin, params: { email: email }

      delete!(victim)

      leftovers = PublicActivity::Activity.where("parameters ILIKE ? OR parameters ILIKE ? OR parameters ILIKE ?", "%Zelda%", "%Quixote%", "%#{email}%")
      expect(leftovers.map(&:key)).to be_empty
      expect(Directory::Person.exists?(person.id)).to be(false)
    end

    it "scrubs rows tied to a directory person they no longer have, and lookups of a past email" do
      old_email = victim.primary_email
      person = Directory::Person.create!(identity: victim, created_by_identity_id: admin.id)
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: group, member_person: person, created_by_identity_id: admin.id)
      end
      Directory.mutate!(cause: "test") { person.reload.destroy! }
      group.create_activity :email_lookup_miss, owner: admin, params: { email: old_email }
      victim.update!(primary_email: "zelda.new@example.com")

      delete!(victim)

      leftovers = PublicActivity::Activity.where(
        "parameters ILIKE ? OR parameters ILIKE ? OR parameters ILIKE ?", "%Zelda%", "%Quixote%", "%#{old_email}%"
      )
      expect(leftovers.map(&:key)).to be_empty
    end

    it "only scrubs exact past addresses, not other people whose email contains one" do
      victim.update!(primary_email: "al@example.com")
      sal = create(:identity, first_name: "Sal", last_name: "Other", primary_email: "sal@example.com")
      sal_person = Directory::Person.create!(identity: sal, created_by_identity_id: admin.id)
      group.create_activity :email_lookup_miss, owner: admin, params: { email: "sal@example.com" }

      delete!(victim)

      expect(PublicActivity::Activity.where(trackable: sal_person, key: "directory_person.create").sole.parameters["email"]).to eq("sal@example.com")
      expect(PublicActivity::Activity.where(key: "directory_collection.email_lookup_miss").sole.parameters).to include("email" => "sal@example.com")
    end

    it "doesn't treat an email change they never completed as an address they held" do
      create(:email_change_request, identity: victim, new_email: "bob@example.com")
      bob = create(:identity, first_name: "Bob", last_name: "Else", primary_email: "bob@example.com")
      bob_person = Directory::Person.create!(identity: bob, created_by_identity_id: admin.id)

      delete!(victim)

      expect(PublicActivity::Activity.where(trackable: bob_person, key: "directory_person.create").sole.parameters["email"]).to eq("bob@example.com")
    end

    it "counts the address an uncompleted email change started from as theirs" do
      old_email = victim.primary_email
      # set without a version, so only the change request remembers it
      create(:email_change_request, identity: victim, old_email: old_email, new_email: "zelda.next@example.com")
      victim.update_columns(primary_email: "zelda.now@example.com")
      PaperTrail::Version.where(item_type: "Identity", item_id: victim.id).delete_all
      group.create_activity :email_lookup_miss, owner: admin, params: { email: old_email }

      delete!(victim)

      expect(PublicActivity::Activity.where("parameters ILIKE ?", "%#{old_email}%")).to be_empty
    end

    it "scrubs their rows under an address they gave up, but not the new holder's" do
      travel_to(10.days.ago) do
        victim.update!(primary_email: "x@example.com")
        old_person = Directory::Person.create!(identity: victim, created_by_identity_id: admin.id)
        Directory.mutate!(cause: "test") { old_person.reload.destroy! }
        victim.update!(primary_email: "y@example.com")
      end
      bob = create(:identity, first_name: "Bob", last_name: "Else", primary_email: "x@example.com")
      bob_person = Directory::Person.create!(identity: bob, created_by_identity_id: admin.id)

      delete!(victim)

      expect(PublicActivity::Activity.where("parameters ILIKE ?", "%Zelda%")).to be_empty
      expect(PublicActivity::Activity.where(trackable: bob_person, key: "directory_person.create").sole.parameters["email"]).to eq("x@example.com")
    end

    it "looks the directory person up under the directory lock" do
      Directory::Person.create!(identity: victim, created_by_identity_id: admin.id)
      held = nil
      allow(Directory::Person).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        held ||= ActiveRecord::Base.connection.select_value(
          "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND objid = #{Directory::Rebuild::LOCK_KEY}"
        ).to_i.positive?
        original.call(*args, **kwargs)
      end

      delete!(victim)

      expect(held).to be(true)
    end

    it "scrubs directory rows written about an existing person after step 10 but before the lock" do
      person = Directory::Person.create!(identity: victim, created_by_identity_id: admin.id)
      raced = false
      allow(Directory).to receive(:lock!).and_wrap_original do |original|
        # a concurrent add that committed between the step 10 scrub and the lock
        unless raced
          raced = true
          group.create_activity :member_added, owner: admin, recipient: person,
            params: { member_name: "Zelda Quixote", member_type: "person" }
        end
        original.call
      end

      delete!(victim)

      expect(PublicActivity::Activity.where("parameters ILIKE ?", "%Zelda%").map(&:key)).to be_empty
    end

    it "makes person creation wait on the directory lock" do
      locked = nil
      allow(Directory).to receive(:lock!).and_wrap_original do |original|
        original.call
        locked = true
      end

      Directory::Person.create!(identity: create(:identity), created_by_identity_id: admin.id)

      expect(locked).to be(true)
    end

    it "can't be undone by adding the deleted identity back afterwards" do
      delete!(victim)
      person = Directory::Person.new(identity: victim, created_by_identity_id: admin.id)
      expect(person).not_to be_valid
    end

    it "records their removal from each collection, redacted" do
      person = Directory::Person.create!(identity: victim, created_by_identity_id: admin.id)
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: group, member_person: person, created_by_identity_id: admin.id)
      end
      allow(Sentry).to receive(:capture_exception)

      delete!(victim)

      removed = PublicActivity::Activity.where(key: "directory_collection.member_removed", trackable: group).sole
      expect(removed.parameters["member_name"]).to eq("[REDACTED] [REDACTED]")
      expect(Sentry).not_to have_received(:capture_exception)
    end

    it "keeps the details of directory changes they made to other people" do
      other = Directory::Person.create!(identity: create(:identity, first_name: "Bystander"), created_by_identity_id: admin.id)
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: group, member_person: other, created_by_identity_id: admin.id)
      end
      group.create_activity :member_expiry_changed, owner: victim, recipient: other,
        params: { member_name: "Bystander X", member_type: "person", expires_at: "2027-01-01T04:59:59Z" }

      delete!(victim)

      row = PublicActivity::Activity.find_by!(key: "directory_collection.member_expiry_changed")
      expect(row.parameters).to include("expires_at" => "2027-01-01T04:59:59Z", "member_name" => "Bystander X")
    end

    it "still revokes the deleted person's app access" do
      app = create(:program, :with_groups)
      entitlement = create(:directory_entitlement)
      Directory::Exposure.create!(app: app, entitlement: entitlement, claim_name: "staff")
      person = Directory::Person.create!(identity: victim, created_by_identity_id: admin.id)
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: entitlement, member_person: person, created_by_identity_id: admin.id)
      end

      expect { delete!(victim) }.to have_enqueued_job(Directory::AfterChangeJob)
        .with(hash_including(revocations: [ hash_including(identity_id: victim.id, app_ids: [ app.id ]) ]))
    end

    it "doesn't discard batched AfterChangeJobs that carry other people's revocations" do
      bystander = create(:identity)
      payload = { "change_ids" => [], "revocations" => [
        { "identity_id" => victim.id, "email" => victim.primary_email, "app_ids" => [ 1 ] },
        { "identity_id" => bystander.id, "email" => bystander.primary_email, "app_ids" => [ 1 ] }
      ] }
      batch = GoodJob::Job.create!(
        active_job_id: SecureRandom.uuid, queue_name: "default", job_class: "Directory::AfterChangeJob",
        serialized_params: { "job_class" => "Directory::AfterChangeJob", "arguments" => [ payload ] }
      )
      own = GoodJob::Job.create!(
        active_job_id: SecureRandom.uuid, queue_name: "default", job_class: "SomeIdentityJob",
        serialized_params: { "job_class" => "SomeIdentityJob", "arguments" => [ { "identity_id" => victim.id } ] }
      )

      delete!(victim)

      expect(batch.reload.finished_at).to be_nil
      expect(own.reload.finished_at).to be_present
    end
  end
end
