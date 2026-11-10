# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory read pages for things the viewer can't see", type: :request do
  let(:viewer) { create(:directory_person) }
  let(:visible) { create(:directory_group, slug: "visible") }
  let(:hidden) { create(:directory_entitlement, slug: "hidden") }
  let(:hidden_person) { create(:directory_person) }

  before do
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: viewer)
      Directory::Grant.create!(grantee_group: grantee, target_collection: visible, permission: "view")
      Directory::Membership.create!(collection: hidden, member_person: hidden_person)
    end
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(viewer.identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "answers 404 for a hidden collection, the same as a missing one" do
    %w[hidden does-not-exist].each do |slug|
      get directory_collection_path(slug)
      expect(response).to have_http_status(:not_found), "show #{slug}"
      get activity_directory_collection_path(slug)
      expect(response).to have_http_status(:not_found), "activity #{slug}"
      get export_directory_collection_path(slug)
      expect(response).to have_http_status(:not_found), "export #{slug}"
      get edit_directory_collection_path(slug)
      expect(response).to have_http_status(:not_found), "edit #{slug}"
    end
  end

  it "answers 404 for a hidden person" do
    get directory_person_path(hidden_person)
    expect(response).to have_http_status(:not_found)
  end

  it "still shows what the viewer can see" do
    get directory_collection_path("visible")
    expect(response).to have_http_status(:ok)
  end
end
