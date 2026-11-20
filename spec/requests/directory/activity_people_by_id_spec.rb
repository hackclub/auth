# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory activity names people by id", type: :request do
  let(:admin) { create(:identity) }
  let(:identity) { create(:identity, first_name: "Zelda", last_name: "Quux", primary_email: "zelda@example.com") }
  let(:group) { create(:directory_group, name: "Crew") }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin.reload)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "stores ids, not names or emails, and renders the person live" do
    person = Directory::Person.find_or_create_for_identity!(identity, created_by: admin)
    Directory.mutate!(cause: "test") { Directory::Membership.create!(collection: group, member_person: person) }

    rows = PublicActivity::Activity.where(key: %w[directory_person.create directory_collection.member_added])
    expect(rows.map { |a| a.parameters.to_json }.join).not_to include("Zelda", "zelda@example.com")

    get directory_activity_path
    expect(response.body).to include("Zelda Quux")
  end

  it "shows a deleted person as [deleted user]" do
    person = Directory::Person.find_or_create_for_identity!(identity, created_by: admin)
    Directory.mutate!(cause: "test") { Directory::Membership.create!(collection: group, member_person: person) }
    identity.update_columns(deleted_at: Time.current)

    get directory_activity_path
    expect(response.body).to include("[deleted user]")
    expect(response.body).not_to include("Zelda")
  end
end
