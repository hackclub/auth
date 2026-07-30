require "rails_helper"

RSpec.describe SAMLAccountSelection, type: :controller do
  controller(ApplicationController) do
    include SAMLAccountSelection
    skip_before_action :authenticate_identity!

    def replay_url
      render plain: saml_replay_url
    end
  end

  before do
    routes.draw { get "replay_url" => "anonymous#replay_url" }
  end

  it "removes the one-shot chooser trigger from a parked SAML URL" do
    get :replay_url, params: {
      SAMLRequest: "request",
      RelayState: "state",
      select_account: "1"
    }

    query = Rack::Utils.parse_query(URI.parse(response.body).query)
    expect(query).to include("SAMLRequest" => "request", "RelayState" => "state")
    expect(query).not_to have_key("select_account")
  end
end
