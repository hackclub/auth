# frozen_string_literal: true

require "rails_helper"

# Adding by email answers "does this address have an hca account?", so SPEC §3.1 promises
# every lookup is audited and each person is rate limited. A batch is one request, so its
# size is capped too.
RSpec.describe "Directory add-by-identifier limits", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def manager_of(collection)
    manager = create(:directory_person)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: manager, created_by_identity_id: manager.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: "manage_members", created_by_identity_id: manager.identity_id)
    end
    manager
  end

  def add_one(email)
    post directory_collection_memberships_path(group.slug), params: { email: email }
  end

  def add_batch(identifiers)
    post batch_create_directory_collection_memberships_path(group.slug), params: { identifiers: identifiers }
  end

  def member?(person)
    Directory::Membership.where(collection: group, member_person: person).exists?
  end

  def misses_by(identity)
    PublicActivity::Activity.where(key: "directory_collection.email_lookup_miss", owner: identity).count
  end

  let(:limit) { Directory::MembershipsController::ADD_RATE_LIMIT }
  let(:cap) { Directory::MembershipsController::MAX_BATCH_IDENTIFIERS }
  let(:group) { create(:directory_group) }
  let(:target) { create(:directory_person) }

  # the test env's :null_store never counts, so give the limit a real store
  around do |example|
    store = Directory::MembershipsController::ADD_RATE_STORE
    original = store.__getobj__
    store.__setobj__(ActiveSupport::Cache::MemoryStore.new)
    begin
      example.run
    ensure
      store.__setobj__(original)
    end
  end

  describe "per-person rate limit" do
    it "refuses adds past the limit, with one budget across both add actions" do
      sign_in manager_of(group).identity
      limit.times { |i| i.even? ? add_one("nobody#{i}@example.com") : add_batch([ "nobody#{i}@example.com" ]) }

      add_batch([ target.primary_email ])

      expect(response).to redirect_to(directory_collection_path(group.slug))
      expect(flash[:alert]).to eq(I18n.t!("directory.flash.add_rate_limited"))
      expect(member?(target)).to be(false)

      add_one(target.primary_email)
      expect(flash[:alert]).to eq(I18n.t!("directory.flash.add_rate_limited"))
      expect(member?(target)).to be(false)
    end

    it "is per person" do
      sign_in manager_of(group).identity
      (limit + 1).times { |i| add_one("nobody#{i}@example.com") }
      expect(flash[:alert]).to eq(I18n.t!("directory.flash.add_rate_limited"))

      sign_in manager_of(group).identity
      add_one(target.primary_email)

      expect(member?(target)).to be(true)
    end

    it "doesn't apply to directory admins, who can search every identity anyway" do
      admin = create(:identity)
      create(:backend_user, identity: admin, directory_services_admin: true)
      sign_in admin.reload
      (limit + 1).times { |i| add_one("nobody#{i}@example.com") }

      add_one(target.primary_email)

      expect(member?(target)).to be(true)
    end
  end

  describe "batch size cap" do
    it "refuses a batch over the cap before looking anything up" do
      manager = manager_of(group)
      sign_in manager.identity
      identifiers = Array.new(cap) { |i| "nobody#{i}@example.com" } + [ target.primary_email ]

      add_batch(identifiers)

      expect(response).to redirect_to(directory_collection_path(group.slug))
      expect(flash[:alert]).to eq(I18n.t!("directory.flash.batch_too_many", max: cap))
      expect(member?(target)).to be(false)
      expect(misses_by(manager.identity)).to eq(0)
    end

    it "takes a batch right at the cap, counting each address once" do
      sign_in manager_of(group).identity
      identifiers = Array.new(cap - 1) { |i| "nobody#{i}@example.com" } + [ target.primary_email ] * 2

      add_batch(identifiers)

      expect(flash[:alert]).to be_nil
      expect(member?(target)).to be(true)
    end
  end

  describe "auditing" do
    it "records batch misses the same way single-add misses are recorded" do
      manager = manager_of(group)
      sign_in manager.identity

      expect { add_one("nobody@example.com") }.to change { misses_by(manager.identity) }.by(1)
      expect { add_batch([ "nobody1@example.com", "nobody2@example.com", target.primary_email ]) }
        .to change { misses_by(manager.identity) }.by(2)
      expect(member?(target)).to be(true)
    end
  end
end
