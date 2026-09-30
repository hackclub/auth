require "rails_helper"

RSpec.describe "API discoverability from public pages", type: :request do
  describe "a public page" do
    it "advertises the API descriptions with IANA service link relations" do
      get "/welcome"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<link rel="service-desc" type="application/vnd.oai.openapi+json" href="/openapi.json">'
      )
      expect(response.body).to include('<link rel="service-doc" type="text/html" href="/docs/api">')
      expect(response.body).to include(
        '<link rel="service-meta" type="application/json" href="/.well-known/oauth-protected-resource">'
      )
    end
  end

  describe "GET /docs/api" do
    before { get "/docs/api" }

    it "renders" do
      expect(response).to have_http_status(:ok)
    end

    it "links to every machine-readable description" do
      expect(response.body).to include("http://www.example.com/openapi.json")
      expect(response.body).to include("http://www.example.com/.well-known/oauth-protected-resource")
      expect(response.body).to include("/.well-known/oauth-authorization-server")
      expect(response.body).to include("/.well-known/api-catalog")
    end

    it "documents every error code the API can return" do
      APIErrors::CATALOG.each_key do |code|
        expect(response.body).to include("<code>#{code}</code>")
      end
    end
  end

  describe "robots.txt" do
    it "does not disallow the machine-readable paths" do
      robots = Rails.root.join("public/robots.txt").read

      expect(robots).not_to match(/^Disallow:/)
      expect(robots).to include("/openapi.json")
      expect(robots).to include("/.well-known/")
    end
  end
end
