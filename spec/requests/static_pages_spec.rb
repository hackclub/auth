require "rails_helper"

RSpec.describe "StaticPages", type: :request do
  describe "GET /oauth/welcome" do
    let(:program) { create(:program) }

    it "renders successfully" do
      get oauth_welcome_path

      expect(response).to have_http_status(:ok)
    end

    it "extracts client_id from return_to URL" do
      return_to = "/oauth/authorize?client_id=#{program.uid}&response_type=code"

      get oauth_welcome_path, params: { return_to: return_to }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(program.name)
    end

    context "with login_hint parameter" do
      it "prefills email field when login_hint is a valid email" do
        return_to = "/oauth/authorize?client_id=#{program.uid}&response_type=code&login_hint=user@example.com"

        get oauth_welcome_path, params: { return_to: return_to }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('value="user@example.com"')
      end

      it "handles URL-encoded login_hint" do
        encoded_email = CGI.escape("test+tag@example.com")
        return_to = "/oauth/authorize?client_id=#{program.uid}&response_type=code&login_hint=#{encoded_email}"

        get oauth_welcome_path, params: { return_to: return_to }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('value="test+tag@example.com"')
      end

      it "ignores invalid email format in login_hint" do
        return_to = "/oauth/authorize?client_id=#{program.uid}&response_type=code&login_hint=not-an-email"

        get oauth_welcome_path, params: { return_to: return_to }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('value="not-an-email"')
      end

      it "ignores empty login_hint" do
        return_to = "/oauth/authorize?client_id=#{program.uid}&response_type=code&login_hint="

        get oauth_welcome_path, params: { return_to: return_to }

        expect(response).to have_http_status(:ok)
      end

      it "does not expose login_hint when return_to is missing" do
        get oauth_welcome_path

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
