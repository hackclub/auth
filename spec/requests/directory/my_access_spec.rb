# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory my access page", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "renders a translated breadcrumb for directory people" do
    sign_in create(:directory_person).identity

    get directory_my_access_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to match(/translation[ _]missing/i)
  end

  it "renders a translated breadcrumb for identities outside the directory" do
    sign_in create(:identity)

    get directory_my_access_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to match(/translation[ _]missing/i)
  end
end
