require "rails_helper"

RSpec.describe "Health check", type: :request do
  describe "GET /up" do
    it "returns 200 when the app can boot" do
      get "/up"

      expect(response).to have_http_status(:ok)
    end
  end
end
