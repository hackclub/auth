require "rails_helper"

RSpec.describe "Backend users update", type: :request do
  let(:super_admin) { create(:backend_user, super_admin: true) }

  before do
    allow_any_instance_of(Backend::ApplicationController).to receive(:current_identity).and_return(super_admin.identity)
    allow_any_instance_of(Backend::ApplicationController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Backend::ApplicationController).to receive(:require_2fa!).and_return(true)
  end

  it "shows why a before_save guard refused the change" do
    last_admin = create(:backend_user, directory_services_admin: true)

    patch backend_user_path(last_admin), params: { backend_user: { directory_services_admin: "0" } }

    expect(response).to redirect_to(backend_users_path)
    expect(flash[:alert]).to include("can't remove the last directory services admin")
    expect(last_admin.reload.directory_services_admin).to be(true)
  end
end
