# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory collection page hidden groups", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def grant!(person, collection, permission, grantee: create(:directory_group))
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission)
    end
  end

  let(:viewer) { create(:directory_person) }
  let(:outer) { create(:directory_group, slug: "outer", name: "Outer Visible Group") }
  let(:hidden_inner) { create(:directory_group, slug: "hidden-inner", name: "Hidden Inner Circle") }
  let(:hidden_grantee) { create(:directory_group, slug: "hidden-grantee", name: "Secret Grantee Team") }

  before do
    # nested via a request-free mutate! so the activity records the group id
    Directory.mutate!(cause: "test") { Directory::Membership.create!(collection: outer, member_group: hidden_inner) }
    Directory.mutate!(cause: "test") { Directory::Grant.create!(grantee_group: hidden_grantee, target_collection: outer, permission: "view") }
    grant!(viewer, outer, "manage_members")
    sign_in viewer.identity
  end

  it "doesn't name or link nested groups or grantee groups the viewer can't see" do
    get directory_collection_path(outer.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Hidden Inner Circle")
    expect(response.body).not_to include(directory_collection_path("hidden-inner"))
    expect(response.body).not_to include("Secret Grantee Team")
    expect(response.body).not_to include(directory_collection_path("hidden-grantee"))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("directory.hidden_group")))
  end

  it "doesn't name them in the activity feed either" do
    get activity_directory_collection_path(outer.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Hidden Inner Circle")
  end

  it "names and links groups the viewer can see" do
    grant!(viewer, hidden_inner, "view")

    get directory_collection_path(outer.slug)

    expect(response.body).to include("Hidden Inner Circle")
    expect(response.body).to include(directory_collection_path("hidden-inner"))
  end
end
