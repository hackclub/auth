# frozen_string_literal: true

require "rails_helper"

# The person page only names collections the viewer can see (SPEC §8.3/§8.4): a via path
# through a hidden group reads "via n groups you can't view", and "can manage" lists only
# visible collections.
RSpec.describe "Directory person page hidden collections", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def make_admin(identity)
    bu = Backend::User.find_by(identity: identity) || create(:backend_user, identity: identity)
    bu.update!(directory_services_admin: true)
    identity.reload
    bu
  end

  def grant!(person, collection, permission)
    grantee = create(:directory_group, slug: "g-#{person.id}-#{collection.id}-#{permission.tr('_', '-')}")
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, created_by_identity_id: person.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission, created_by_identity_id: person.identity_id)
    end
    grantee
  end

  def add!(collection, person: nil, group: nil)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: collection, member_person: person, member_group: group, created_by_identity_id: admin_identity.id)
    end
  end

  def hidden_label = ERB::Util.html_escape(I18n.t("directory.collections.show.via_hidden", count: 1))

  let(:admin_identity)  { create(:identity) }
  let(:viewer_identity) { create(:identity) }
  let!(:viewer) { create(:directory_person, identity: viewer_identity) }
  let!(:member) { create(:directory_person) }

  # member is directly in hidden_inner, which sits inside outer; the viewer can see outer only.
  let(:outer)        { create(:directory_group, slug: "outer", name: "Outer Visible Group") }
  let(:hidden_inner) { create(:directory_group, slug: "hidden-inner", name: "Hidden Inner Circle") }
  # and directly in shown_inner, inside other_outer; the viewer can see both.
  let(:other_outer)  { create(:directory_group, slug: "other-outer", name: "Other Outer Group") }
  let(:shown_inner)  { create(:directory_group, slug: "shown-inner", name: "Shown Inner Group") }

  let(:managed_visible) { create(:directory_group, slug: "managed-visible", name: "Managed Visible Team") }
  let(:managed_hidden)  { create(:directory_group, slug: "managed-hidden", name: "Secret Managed Team") }

  before do
    make_admin(admin_identity)

    add!(outer, group: hidden_inner)
    add!(hidden_inner, person: member)
    add!(other_outer, group: shown_inner)
    add!(shown_inner, person: member)

    grant!(member, managed_visible, "manage_members")
    grant!(member, managed_hidden, "manage_members")

    [ outer, other_outer, shown_inner, managed_visible ].each { |c| grant!(viewer, c, "view") }
  end

  it "has a translation for the hidden via label" do
    expect(I18n.exists?("directory.collections.show.via_hidden")).to be(true)
  end

  context "as a non-admin" do
    before do
      sign_in viewer_identity
      get directory_person_path(member)
    end

    it "replaces via segments the viewer can't see with the hidden label" do
      expect(response).to have_http_status(:ok)
      via = controller.instance_variable_get(:@visible_memberships).reject { |m| m[:direct] }

      expect(via.find { |m| m[:collection] == outer }[:via_path]).to be_empty
      expect(via.find { |m| m[:collection] == other_outer }[:via_path]).to eq([ shown_inner ])

      expect(response.body).to include("Outer Visible Group")
      expect(response.body).not_to include("Hidden Inner Circle")
      expect(response.body).not_to include(directory_collection_path(hidden_inner.slug))
      expect(response.body).to include(hidden_label)
      expect(response.body).not_to include("translation_missing")
    end

    it "keeps via segments the viewer can see as links" do
      expect(response.body).to include(%(href="#{directory_collection_path(shown_inner.slug)}"))
    end

    it "lists only the managed collections the viewer can see" do
      expect(controller.instance_variable_get(:@manageable_collections).to_a).to eq([ managed_visible ])
      expect(response.body).to include("Managed Visible Team")
      expect(response.body).not_to include("Secret Managed Team")
    end
  end

  context "as a directory admin" do
    it "names every collection" do
      sign_in admin_identity
      get directory_person_path(member)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hidden Inner Circle")
      expect(response.body).to include("Secret Managed Team")
      expect(response.body).not_to include(hidden_label)
    end
  end
end
