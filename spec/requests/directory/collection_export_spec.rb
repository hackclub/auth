# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Directory collection export", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def make_admin(identity)
    create(:backend_user, identity: identity).update!(directory_services_admin: true)
    identity.reload
  end

  def add_member(**identity_attrs)
    person = create(:directory_person, identity: create(:identity, **identity_attrs))
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: group, member_person: person, created_by_identity_id: admin.id)
    end
    person.identity
  end

  # The cells a spreadsheet would see once it has undone the CSV quoting.
  def exported_rows
    get export_directory_collection_path(group.slug)
    expect(response).to have_http_status(:ok)
    CSV.parse(response.body)
  end

  let(:admin) { create(:identity) }
  let(:group) { create(:directory_group, slug: "crew") }

  before do
    make_admin(admin)
    sign_in admin
  end

  it "prefixes a quote to a name a spreadsheet would run as a formula" do
    evil = add_member(first_name: '=HYPERLINK("http://evil","x")')

    expect(exported_rows).to include([ %('=HYPERLINK("http://evil","x") Trashworth), evil.primary_email, evil.public_id, "direct" ])
  end

  it "prefixes a quote to an email that starts like a formula" do
    add_member(primary_email: "-2+3@hackclub.com")

    identity = Identity.find_by(primary_email: "-2+3@hackclub.com")
    expect(exported_rows).to include([ "Heidi Trashworth", "'-2+3@hackclub.com", identity.public_id, "direct" ])
  end

  it "leaves ordinary values alone, including ones with those characters past the start" do
    add_member(first_name: "Mary-Jane", last_name: "O'Neil", primary_email: "mary-jane+crew@hackclub.com")

    rows = exported_rows
    expect(rows.first).to eq([ "name", "email", "hca_id", "membership type" ])
    identity = Identity.find_by(primary_email: "mary-jane+crew@hackclub.com")
    expect(rows).to include([ "Mary-Jane O'Neil", "mary-jane+crew@hackclub.com", identity.public_id, "direct" ])
  end
end
