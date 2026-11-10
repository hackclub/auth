# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory membership expiry update", type: :request do
  include ActiveJob::TestHelper

  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  let(:admin) { create(:identity) }
  let(:group) { create(:directory_group, slug: "crew") }
  let(:person) { create(:directory_person) }
  let!(:membership) do
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: group, member_person: person, expires_at: 2.days.from_now, created_by_identity_id: admin.id)
    end
    Directory::Membership.find_by!(collection: group, member_person: person)
  end

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    sign_in admin.reload
  end

  it "extends an expiry without revoking anything" do
    new_date = 30.days.from_now.to_date
    expect {
      patch directory_collection_membership_path(group.slug, membership), params: { expires_at: new_date.iso8601 }
    }.not_to change { Directory::MembershipChange.where(op: "removed").count }

    expect(flash[:notice]).to eq(I18n.t("directory.flash.expiry_updated"))
    expect(Directory::Expiry.date_for(membership.reload.expires_at)).to eq(new_date)
    expect(Directory::Expiry.date_for(Directory::EffectiveMembership.find_by!(person_id: person.id, collection_id: group.id).expires_at)).to eq(new_date)
    expect(PublicActivity::Activity.where(key: "directory_collection.member_expiry_changed")).to exist
  end

  it "logs extending a lapsed membership as a renewal and restores access" do
    membership.update_columns(expires_at: 1.minute.ago)
    Directory.mutate!(cause: "test") { }
    expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: group.id)).not_to exist

    patch directory_collection_membership_path(group.slug, membership), params: { expires_at: 30.days.from_now.to_date.iso8601 }

    expect(PublicActivity::Activity.where(key: "directory_collection.member_expiry_changed").last.parameters["renewed"]).to be(true)
    expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: group.id)).to exist
    get activity_directory_collection_path(group.slug)
    expect(response.body).to include("renewed expired person")
  end

  it "clears an expiry" do
    patch directory_collection_membership_path(group.slug, membership), params: { expires_at: "" }
    expect(membership.reload.expires_at).to be_nil
  end

  it "rejects an invalid date" do
    patch directory_collection_membership_path(group.slug, membership), params: { expires_at: "2027-02-30" }
    expect(flash[:alert]).to eq(I18n.t("directory.flash.invalid_expires_at"))
    expect(membership.reload.expires_at.to_date).to eq(2.days.from_now.to_date)
  end

  it "doesn't let someone without manage_members change it" do
    sign_in create(:identity)
    patch directory_collection_membership_path(group.slug, membership), params: { expires_at: "" }
    expect(membership.reload.expires_at).to be_present
  end

  it "renders the expiry form on the collection page" do
    get directory_collection_path(group.slug)
    expect(response.body).to include(directory_collection_membership_path(group.slug, membership))
    expect(response.body).to include(I18n.t("directory.collections.show.save_expiry"))
  end

  it "names a nested group in its expiry-change activity" do
    child = create(:directory_group, name: "Oncall Crew")
    edge = nil
    Directory.mutate!(cause: "test") { edge = Directory::Membership.create!(collection: group, member_group: child) }

    patch directory_collection_membership_path(group.slug, edge), params: { expires_at: 30.days.from_now.to_date.iso8601 }
    get activity_directory_collection_path(group.slug)

    expect(response.parsed_body.text.squish).to include("set group Oncall Crew in")
  end
end
