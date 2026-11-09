require "rails_helper"

# The backend palette's Directory scope and dper!/dcol! lookups are for directory admins
# only; the backend doesn't run directory policies, so everyone else gets nothing.
RSpec.describe "Backend kbar directory", type: :request do
  let(:collection) { create(:directory_group, slug: "secret-team", name: "Secret Team") }

  def sign_in(user)
    allow_any_instance_of(Backend::ApplicationController).to receive(:current_identity).and_return(user.identity)
    allow_any_instance_of(Backend::ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(Backend::ApplicationController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Backend::ApplicationController).to receive(:require_2fa!).and_return(true)
  end

  context "as a directory admin" do
    before { sign_in create(:backend_user, directory_services_admin: true) }

    it "resolves dcol! ids to the directory page" do
      get backend_kbar_search_path, params: { q: collection.public_id }
      expect(response.parsed_body).to contain_exactly(include("label" => "Secret Team", "path" => "/directory/collections/secret-team"))
    end

    it "searches the directory scope" do
      collection
      get backend_kbar_search_path, params: { q: "secret", scope: "directory" }
      expect(response.parsed_body.pluck("path")).to include("/directory/collections/secret-team")
    end
  end

  context "as a plain backend user" do
    before { sign_in create(:backend_user) }

    it "doesn't resolve dcol! ids" do
      get backend_kbar_search_path, params: { q: collection.public_id }
      expect(response.parsed_body).to eq([])
    end

    it "doesn't 500 on a query of only bangs" do
      get backend_kbar_search_path, params: { q: "!!" }
      expect(response).to have_http_status(:ok)
    end

    it "doesn't advertise directory prefixes" do
      user = create(:backend_user)
      expect(JSON.parse(Shortcodes.kbar_data_for(user))["prefixes"].keys).not_to include("dcol", "dper")
    end
  end
end
