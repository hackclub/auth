# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Re-adding members with expired memberships", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def expire_membership!(membership)
    membership.update_columns(expires_at: 1.hour.ago)
    Directory::Rebuild.call(cause: "test-expire", skip_lock: false)
  end

  let(:admin) { create(:identity) }
  let(:group) { create(:directory_group, slug: "crew") }
  let(:person) { create(:directory_person) }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    sign_in admin.reload
  end

  describe "single create" do
    it "replaces an expired membership when re-adding by email" do
      membership = nil
      Directory.mutate!(cause: "test") do
        membership = Directory::Membership.create!(
          collection: group, member_person: person,
          expires_at: 1.day.from_now, created_by_identity_id: admin.id
        )
      end
      expire_membership!(membership)

      expect(Directory::EffectiveMembership.where(collection_id: group.id, person_id: person.id)).not_to exist

      post directory_collection_memberships_path(group.slug), params: { email: person.primary_email }

      expect(response).to redirect_to(directory_collection_path(group.slug))
      expect(flash[:notice]).to eq(I18n.t("directory.flash.member_added"))
      expect(Directory::Membership.active.where(collection: group, member_person: person)).to exist
    end

    it "rejects adding an already-active member" do
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(
          collection: group, member_person: person,
          created_by_identity_id: admin.id
        )
      end

      post directory_collection_memberships_path(group.slug), params: { email: person.primary_email }

      expect(response).to redirect_to(directory_collection_path(group.slug))
      expect(flash[:alert]).to eq(I18n.t("directory.flash.already_a_member"))
    end
  end

  describe "batch_create" do
    it "re-adds expired members instead of skipping them" do
      membership = nil
      Directory.mutate!(cause: "test") do
        membership = Directory::Membership.create!(
          collection: group, member_person: person,
          expires_at: 1.day.from_now, created_by_identity_id: admin.id
        )
      end
      expire_membership!(membership)

      post batch_create_directory_collection_memberships_path(group.slug),
        params: { identifiers: [ person.primary_email ] }

      expect(response).to redirect_to(directory_collection_path(group.slug))
      expect(flash[:notice]).to include(I18n.t("directory.flash.batch_added", count: 1))
      expect(Directory::Membership.active.where(collection: group, member_person: person)).to exist
    end

    it "skips active members and reports them" do
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(
          collection: group, member_person: person,
          created_by_identity_id: admin.id
        )
      end

      post batch_create_directory_collection_memberships_path(group.slug),
        params: { identifiers: [ person.primary_email ] }

      expect(flash[:notice]).to include(I18n.t("directory.flash.batch_skipped", count: 1))
    end

    it "does not crash when a single row in the batch fails" do
      other = create(:directory_person)

      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(
          collection: group, member_person: person,
          created_by_identity_id: admin.id
        )
      end

      post batch_create_directory_collection_memberships_path(group.slug),
        params: { identifiers: [ person.primary_email, other.primary_email ] }

      expect(response).to redirect_to(directory_collection_path(group.slug))
      expect(Directory::Membership.active.where(collection: group, member_person: other)).to exist
    end
  end
end
