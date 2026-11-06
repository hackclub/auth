# frozen_string_literal: true

require "rails_helper"

# deactivate! is the backend's offboarding switch. Directory root is exercised
# from a normal HCA session, outside Backend::ApplicationController's active?
# gate, so a deactivated staffer has to lose it there too.
RSpec.describe "Directory root for deactivated backend users", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def grant!(person, collection, permission)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, created_by_identity_id: person.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission, created_by_identity_id: person.identity_id)
    end
  end

  let(:staffer) { create(:identity) }
  let!(:backend_user) { create(:backend_user, identity: staffer, directory_services_admin: true) }
  let(:staffer_person) { Directory::Person.find_by!(identity: staffer) }

  # someone else's app, gated on an entitlement the staffer holds nothing on
  let(:oauth_app) { create(:program, owner_identity: create(:identity), trust_level: :hq_official) }
  let(:entitlement) { create(:directory_entitlement, slug: "staff-only", name: "Staff Only Entitlement") }

  before { Directory::AppRequirement.create!(app: oauth_app, entitlement: entitlement) }

  def requirement = Directory::AppRequirement.where(app: oauth_app, entitlement: entitlement)
  def unwire_requirement = delete(directory_app_requirement_path(entitlement.slug), params: { app_id: oauth_app.id })

  context "while active" do
    before { sign_in staffer }

    it "is a directory admin" do
      get directory_root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Staff Only Entitlement")

      get directory_all_grants_path
      expect(response).to have_http_status(:ok)
    end

    it "can unwire a requirement on an app it doesn't own" do
      unwire_requirement
      expect(response).to redirect_to(developer_app_path(oauth_app))
      expect(requirement).not_to exist
    end
  end

  context "once deactivated" do
    before do
      backend_user.deactivate!
      staffer.reload # drop any cached backend_user
      sign_in staffer
    end

    it "gets the not-found gate on /directory" do
      get directory_root_path
      expect(response).to have_http_status(:not_found)
    end

    it "cannot unwire a requirement through the admin path" do
      unwire_requirement
      expect(response).to redirect_to(root_path)
      expect(requirement).to exist
    end

    it "cannot unwire an exposure through the admin path" do
      exposure = Directory::Exposure.create!(app: oauth_app, entitlement: entitlement, claim_name: "staff")
      delete directory_exposure_path(exposure)
      expect(response).to redirect_to(root_path)
      expect(Directory::Exposure.where(id: exposure.id)).to exist
    end

    it "is root again after activate!" do
      backend_user.activate!
      staffer.reload
      get directory_all_grants_path
      expect(response).to have_http_status(:ok)
    end

    # A grant gets them past the gate as an ordinary delegated user, so these
    # hit the admin checks themselves rather than the gate.
    context "with a manage_members grant" do
      let(:team) { create(:directory_group, slug: "team", name: "Team") }

      before { grant!(staffer_person, team, "manage_members") }

      it "sees only what it was granted" do
        get directory_root_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Team")
        expect(response.body).not_to include("Staff Only Entitlement")
      end

      %i[directory_all_grants_path directory_reports_path directory_health_path directory_view_as_path
         directory_people_path directory_activity_path directory_new_import_path].each do |path_helper|
        it "is denied #{path_helper}" do
          get send(path_helper)
          expect(response.status).to be_in([302, 404])
        end
      end

      it "cannot create grants" do
        grantee = create(:directory_group)
        post directory_collection_grants_path(team.slug), params: { grantee_group_slug: grantee.slug, permission: "view" }
        expect(response).to redirect_to(directory_root_path)
        expect(Directory::Grant.where(grantee_group: grantee)).not_to exist
      end

      it "cannot add people to an entitlement it holds nothing on" do
        post directory_collection_memberships_path(entitlement.slug), params: { email: create(:identity).primary_email }
        expect(response).to redirect_to(directory_root_path)
        expect(Directory::Membership.where(collection: entitlement)).not_to exist
      end

      it "gets no exact-email lookup outside the directory" do
        get directory_picker_search_path, params: { q: create(:identity).primary_email, scope: "people" }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end
    end
  end

  # view_as answers "what does this person see?" -- for a deactivated admin
  # that's its grants, not the whole directory
  it "view_as shows a deactivated admin's grant-scoped view" do
    viewer = create(:identity)
    create(:backend_user, identity: viewer, directory_services_admin: true)
    backend_user.deactivate!

    sign_in viewer
    get directory_view_as_path, params: { person_id: staffer_person.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Staff Only Entitlement")
  end

  describe "backend users pages" do
    let(:super_admin) { create(:backend_user, :super_admin) }

    before do
      backend_user.deactivate!
      allow_any_instance_of(Backend::ApplicationController).to receive(:current_identity).and_return(super_admin.identity)
      allow_any_instance_of(Backend::ApplicationController).to receive(:authenticate_user!).and_return(true)
      allow_any_instance_of(Backend::ApplicationController).to receive(:require_2fa!).and_return(true)
    end

    it "still show the stored flag for a deactivated user" do
      get edit_backend_user_path(backend_user)
      checkbox = Nokogiri::HTML(response.body).at_css("input[type=checkbox][name='backend_user[directory_services_admin]']")
      expect(checkbox["checked"]).to eq("checked")

      get backend_users_path
      expect(response.body).to include("Directory Services Admin")
    end

    it "save the flag for a deactivated user" do
      patch backend_user_path(backend_user), params: { backend_user: { directory_services_admin: "0" } }
      expect(response).to redirect_to(backend_users_path)
      expect(flash[:notice]).to eq("User updated!")
      expect(backend_user.reload.directory_services_admin).to be(false)
    end
  end
end
