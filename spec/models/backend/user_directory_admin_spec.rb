# frozen_string_literal: true

require "rails_helper"

RSpec.describe Backend::User, "directory services admin" do
  def directory_admin(**attrs) = create(:backend_user, directory_services_admin: true, **attrs)

  describe "#directory_services_admin?" do
    it "is true for an active user with the flag" do
      expect(directory_admin).to be_directory_services_admin
    end

    it "is false for an active user without the flag" do
      expect(create(:backend_user)).not_to be_directory_services_admin
    end

    it "goes false on deactivate! but keeps the stored flag and role label" do
      user = directory_admin
      user.deactivate!
      user.reload

      expect(user).not_to be_directory_services_admin
      expect(user.directory_services_admin).to be(true)
      expect(user.pretty_roles).to include("Directory Services Admin")
    end

    it "comes back on activate!" do
      user = directory_admin(active: false)
      user.activate!
      expect(user.reload).to be_directory_services_admin
    end
  end

  it "still enrolls a directory person when the flag is set on an inactive user" do
    user = create(:backend_user, active: false)
    user.update!(directory_services_admin: true)
    expect(Directory::Person.where(identity_id: user.identity_id)).to exist
  end

  describe "last-admin guard" do
    it "doesn't count deactivated admins, so the last active one can't be stripped" do
      last_active = directory_admin
      directory_admin.deactivate!

      expect(last_active.update(directory_services_admin: false)).to be(false)
      expect(last_active.errors[:directory_services_admin]).to include("can't remove the last directory services admin")
      expect(last_active.reload.directory_services_admin).to be(true)
    end

    it "allows stripping an admin while another active one remains" do
      directory_admin
      other = directory_admin
      expect(other.update(directory_services_admin: false)).to be(true)
    end

    # it isn't root, so clearing it never costs a working admin
    it "allows stripping a deactivated admin even when no active admin is left" do
      former = directory_admin(active: false)
      expect(former.update(directory_services_admin: false)).to be(true)
    end

    # offboarding has to work even for the last admin; a super admin can
    # grant the flag to someone else afterwards
    it "never blocks deactivating the last active admin" do
      last_active = directory_admin
      last_active.deactivate!
      expect(last_active.reload).not_to be_active
    end
  end
end
