# frozen_string_literal: true

require "rails_helper"

# rescue_from picks the most recently declared handler, so a catch-all declared after
# the specific ones silently turns every 404 into a 500. local envs re-raise from the
# catch-all, which is why this has to pretend to be production to see it.
RSpec.describe "Error pages", type: :request do
  let(:identity) { create(:identity) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
    allow(Rails.env).to receive(:local?).and_return(false)
  end

  it "renders a 404, not a 500, for a missing record" do
    allow_any_instance_of(StaticPagesController).to receive(:home).and_raise(ActiveRecord::RecordNotFound)

    get root_path

    expect(response).to have_http_status(:not_found)
  end

  it "renders a 404 for a RoutingError raised by a controller gate" do
    allow_any_instance_of(StaticPagesController).to receive(:home).and_raise(ActionController::RoutingError, "Not Found")

    get root_path

    expect(response).to have_http_status(:not_found)
  end

  it "renders a 422, not a 500, for a stale form" do
    allow_any_instance_of(StaticPagesController).to receive(:home).and_raise(ActionController::InvalidAuthenticityToken)

    get root_path

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders the html 404 for a non-html request" do
    create(:backend_user, identity: identity, directory_services_admin: true)
    identity.reload

    get export_directory_collection_path("no-such-collection", format: :csv)

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("text/html")
  end

  it "still renders a 500 for everything else" do
    allow_any_instance_of(StaticPagesController).to receive(:home).and_raise(RuntimeError, "boom")

    get root_path

    expect(response).to have_http_status(:internal_server_error)
  end
end
