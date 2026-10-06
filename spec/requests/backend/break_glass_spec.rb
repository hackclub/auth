require "rails_helper"

RSpec.describe "Backend break glass", type: :request do
  let(:staff) { create(:backend_user, can_break_glass: true) }
  let(:current_user) { staff }

  before do
    allow_any_instance_of(Backend::ApplicationController).to receive(:current_identity).and_return(current_user.identity)
    allow_any_instance_of(Backend::ApplicationController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Backend::ApplicationController).to receive(:require_2fa!).and_return(true)
  end

  describe "POST /backend/break_glass for a VerificationCase::Document" do
    let(:kase) { create(:verification_case, :docs_submitted) }
    let(:doc) { create(:verification_case_document, verification_case: kase) }
    let(:case_events) { kase.events.where(key: "document_break_glass") }

    def break_glass(reason:)
      post backend_break_glass_path, params: {
        break_glassable_type: "VerificationCase::Document",
        break_glassable_id: doc.id,
        reason: reason
      }
    end

    it "records the access and logs exactly one case event carrying the reason" do
      expect { break_glass(reason: "reviewing the primary document for the call") }
        .to change { BreakGlassRecord.where(break_glassable: doc).count }.by(1)

      record = BreakGlassRecord.where(break_glassable: doc).sole
      expect(record.backend_user).to eq(staff)
      expect(record.reason).to eq("reviewing the primary document for the call")

      event = case_events.sole
      expect(event.actor).to eq(staff)
      expect(event.data).to include("document_id" => doc.id, "reason" => "reviewing the primary document for the call")
      expect(flash[:notice]).to include("Access granted")
    end

    # the event trail is append-only, so a phantom access can't be cleaned up later
    it "writes no case event when the reason is blank and the record fails to save" do
      expect { break_glass(reason: "") }.not_to change(BreakGlassRecord, :count)

      expect(case_events).not_to exist
      expect(flash[:alert]).to include("Reason can't be blank")
    end

    context "when the user cannot break glass" do
      let(:current_user) { create(:backend_user, can_break_glass: false) }

      it "refuses and writes neither a record nor a case event" do
        expect { break_glass(reason: "trying anyway") }.not_to change(BreakGlassRecord, :count)

        expect(case_events).not_to exist
        expect(response).to redirect_to(backend_root_path)
        expect(flash[:error]).to include("authorized to do that")
      end
    end

    it "rolls the record back when the case event cannot be written" do
      allow_any_instance_of(VerificationCase).to receive(:log_event!).and_raise(ActiveRecord::RecordInvalid)

      expect { break_glass(reason: "a reason that would otherwise be fine") }.not_to change(BreakGlassRecord, :count)

      expect(case_events).not_to exist
    end
  end

  describe "POST /backend/break_glass for an identity document" do
    it "still records the access without touching any case trail" do
      identity_doc = create(:identity_document)

      expect {
        post backend_break_glass_path, params: {
          break_glassable_type: "Identity::Document",
          break_glassable_id: identity_doc.id,
          reason: "checking a mismatch"
        }
      }.to change { BreakGlassRecord.where(break_glassable: identity_doc).count }.by(1)

      expect(VerificationCase::Event.where(key: "document_break_glass")).not_to exist
    end
  end
end
