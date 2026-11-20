# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Collection page member counts", type: :request do
  let(:admin) { create(:identity) }
  let(:group) { create(:directory_group, slug: "crew") }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    admin.reload
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)

    Directory.mutate!(cause: "test") do
      2.times { Directory::Membership.create!(collection: group, member_person: create(:directory_person)) }
      Directory::Membership.create!(collection: group, member_group: create(:directory_group))
      Directory::Membership.create!(collection: group, member_person: create(:directory_person), expires_at: 1.day.from_now)
        .update_columns(expires_at: 1.hour.ago)
    end
  end

  it "agrees between the header and the members badge" do
    get directory_collection_path(group.slug)

    text = response.parsed_body.text.squish
    expect(text).to include("2 people")
    expect(text).to include("2 people · 1 group")
    expect(text).to include("+1 expired")
  end
end
