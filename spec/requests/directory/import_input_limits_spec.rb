# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory CSV import input limits", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  let(:admin) { create(:identity) }
  let!(:backend_user) { create(:backend_user, identity: admin, directory_services_admin: true) }
  let!(:team) { create(:directory_group, slug: "team") }

  before { sign_in admin }

  let(:oversized) { "someone@example.com,team\n" * ((Directory::Import::MAX_CSV_BYTES / 24) + 1) }

  it "applies the size limit to pasted text on preview" do
    post directory_import_preview_path, params: { csv_text: oversized }
    expect(response).to redirect_to(directory_new_import_path)
    expect(flash[:alert]).to eq(I18n.t("directory.import.file_too_large"))
  end

  it "applies the size limit to the preview's re-post on apply" do
    expect {
      post directory_import_path, params: { csv_text: oversized }
    }.not_to change(Directory::Membership, :count)
    expect(response).to redirect_to(directory_new_import_path)
    expect(flash[:alert]).to eq(I18n.t("directory.import.file_too_large"))
  end

  it "previews malformed CSV as an error instead of a 500" do
    post directory_import_preview_path, params: { csv_text: %(a@example.com,"team\n) }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("couldn&#39;t parse CSV")
  end
end
