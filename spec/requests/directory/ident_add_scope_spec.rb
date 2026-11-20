# frozen_string_literal: true

require "rails_helper"

# Public IDs are guessable (unsalted hashids over sequential ids), so a non-admin adding
# by ident! must not be able to reach identities outside the directory.
RSpec.describe "Directory add-by-ident! scope", type: :request do
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

  def add(identifier, via:)
    if via == :create
      post directory_collection_memberships_path(group.slug), params: { email: identifier }
    else
      post batch_create_directory_collection_memberships_path(group.slug), params: { identifiers: [ identifier ] }
    end
  end

  def member?(identity)
    Directory::Membership.joins(:member_person).where(collection: group, directory_people: { identity_id: identity.id }).exists?
  end

  let(:group) { create(:directory_group) }
  let(:outsider) { create(:identity) } # an identity with no directory person

  %i[create batch_create].each do |action|
    context "via #{action}" do
      context "as a manager" do
        before do
          manager = create(:directory_person)
          grant!(manager, group, "manage_members")
          sign_in manager.identity
        end

        it "treats the ident! of a non-directory identity as not found" do
          expect { add(outsider.public_id, via: action) }.not_to change(Directory::Person, :count)

          expect(response).to redirect_to(directory_collection_path(group.slug))
          if action == :create
            expect(flash[:alert]).to eq(I18n.t("directory.flash.email_not_found"))
          else
            expect(flash[:notice]).to eq(I18n.t("directory.flash.batch_not_found", count: 1, items: outsider.public_id))
          end
          expect(member?(outsider)).to be(false)
        end

        it "adds the ident! of someone already in the directory" do
          insider = create(:directory_person)

          add(insider.identity.public_id, via: action)

          expect(response).to redirect_to(directory_collection_path(group.slug))
          expect(member?(insider.identity)).to be(true)
        end
      end

      context "as a directory admin" do
        before do
          admin = create(:identity)
          create(:backend_user, identity: admin, directory_services_admin: true)
          sign_in admin.reload
        end

        it "can bring a non-directory identity in by ident!" do
          expect { add(outsider.public_id, via: action) }.to change(Directory::Person, :count).by(1)

          expect(response).to redirect_to(directory_collection_path(group.slug))
          expect(member?(outsider)).to be(true)
        end
      end
    end
  end
end
