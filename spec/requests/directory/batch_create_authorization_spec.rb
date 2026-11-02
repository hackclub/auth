# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory batch add authorization", type: :request do
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

  def batch_add(collection, identifiers)
    post batch_create_directory_collection_memberships_path(collection.slug), params: { identifiers: identifiers }
  end

  let(:group) { create(:directory_group) }
  let(:existing_person) { create(:directory_person) }
  let(:outside_identity) { create(:identity) }

  def member_people(collection)
    Directory::Membership.where(collection: collection).where.not(member_person_id: nil).map(&:member_person)
  end

  it "lets a directory admin batch add" do
    admin = create(:identity)
    create(:backend_user, identity: admin, directory_services_admin: true)
    sign_in admin.reload

    batch_add(group, [ existing_person.primary_email, outside_identity.primary_email ])

    expect(response).to redirect_to(directory_collection_path(group.slug))
    expect(flash[:notice]).to eq(I18n.t("directory.flash.batch_added", count: 2))
    expect(member_people(group).map(&:identity)).to contain_exactly(existing_person.identity, outside_identity)
  end

  it "lets a manage_members holder batch add to their collection" do
    manager = create(:directory_person)
    grant!(manager, group, "manage_members")
    sign_in manager.identity

    batch_add(group, [ existing_person.primary_email, outside_identity.primary_email ])

    expect(response).to redirect_to(directory_collection_path(group.slug))
    expect(member_people(group).map(&:identity)).to contain_exactly(existing_person.identity, outside_identity)
    expect(Directory::EffectiveMembership.where(collection: group, person: existing_person)).to exist
  end

  it "refuses someone without manage_members on the collection" do
    viewer = create(:directory_person)
    grant!(viewer, group, "view")
    sign_in viewer.identity

    batch_add(group, [ existing_person.primary_email, outside_identity.primary_email ])

    expect(response).to redirect_to(directory_root_path)
    expect(flash[:alert]).to eq(I18n.t("directory.flash.not_authorized"))
    expect(member_people(group)).to be_empty
    expect(Directory::Person.where(identity: outside_identity)).not_to exist
  end
end
