# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory reports: collections nobody can manage", type: :request do
  let(:admin) { create(:identity) }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin.reload)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "counts a recursive grant on a parent, and not a grant to an empty group" do
    parent = create(:directory_group, name: "Parent Group")
    child = create(:directory_group, name: "Child Via Recursion")
    lonely = create(:directory_group, name: "Granted To Nobody")
    managers = create(:directory_group)
    empty = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: parent, member_group: child)
      Directory::Membership.create!(collection: managers, member_person: create(:directory_person))
      Directory::Grant.create!(grantee_group: managers, target_collection: parent, permission: "manage_members", recursive: true)
      Directory::Grant.create!(grantee_group: empty, target_collection: lonely, permission: "manage_members")
    end

    get directory_reports_path

    heading = I18n.t("directory.reports.index.unmanaged_collections")
    section = response.parsed_body.css("details").find { |d| d.at_css("summary")&.text&.include?(heading) }
    expect(section.text).not_to include("Child Via Recursion")
    expect(section.text).to include("Granted To Nobody")
  end
end
