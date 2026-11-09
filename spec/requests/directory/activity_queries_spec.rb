# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory activity pages query count", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def count_queries
    n = 0
    cb = ->(*, payload) { n += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(cb, "sql.active_record") { yield }
    n
  end

  let(:admin) { create(:identity) }
  let(:hub) { create(:directory_group, slug: "hub") }
  let(:subject_person) { create(:directory_person) }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    sign_in admin.reload
  end

  # each row gets its own owner and trackable, so anything loaded per row shows up as growth
  def add_activity_rows(count)
    count.times do
      owner = create(:identity)
      g = create(:directory_group)
      grant = Directory::Grant.create!(grantee_group: g, target_collection: hub, permission: "view")
      hub.create_activity :member_added, owner: owner, recipient: subject_person, params: { member_name: "x", member_type: "person" }
      grant.create_activity :create, owner: owner, recipient: subject_person
      create(:directory_person).create_activity :create, owner: owner, recipient: subject_person
    end
  end

  {
    "the directory activity log" => -> { directory_activity_path },
    "a collection's activity" => -> { activity_directory_collection_path(hub.slug) },
    "a person's page" => -> { directory_person_path(subject_person) }
  }.each do |name, path|
    it "doesn't grow with the number of rows on #{name}" do
      add_activity_rows(2)
      small = count_queries { get instance_exec(&path) }
      add_activity_rows(6)
      large = count_queries { get instance_exec(&path) }

      expect(response).to have_http_status(:ok)
      expect(large).to be <= small
    end
  end
end
