# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory import expires_at", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def make_admin(identity)
    create(:backend_user, identity: identity).update!(directory_services_admin: true)
    identity.reload
  end

  # [email, collection, expires, action] for the changes-table row with this email
  def preview_row(email)
    row = response.parsed_body.css("tbody tr").find { |tr| tr.at_css("td")&.text&.strip == email }
    row&.css("td")&.map { |td| td.text.strip }
  end

  let(:admin) { create(:identity) }
  let(:temp) { create(:identity) }
  let(:permanent) { create(:identity) }
  let!(:group) { create(:directory_group, slug: "temps") }

  before do
    make_admin(admin)
    sign_in admin
  end

  describe "GET /directory/import" do
    it "documents the accepted expires_at formats" do
      get directory_new_import_path

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.text).to include("YYYY-MM-DD (midnight UTC)")
    end
  end

  describe "POST /directory/import/preview" do
    it "shows each row's parsed expiry, or never" do
      post directory_import_preview_path, params: {
        csv_text: "email,collection_slug,expires_at\n" \
                  "#{temp.primary_email},temps,2099-01-01T12:30:00-05:00\n" \
                  "#{permanent.primary_email},temps,\n"
      }

      expect(response).to have_http_status(:ok)
      expect(preview_row(temp.primary_email)).to eq([ temp.primary_email, "temps", "2099-01-01 17:30 UTC", "add" ])
      expect(preview_row(permanent.primary_email)).to eq([ permanent.primary_email, "temps", "never", "add" ])
    end

    it "shows an unparseable expiry as a row error and doesn't offer to apply" do
      post directory_import_preview_path, params: { csv_text: "#{temp.primary_email},temps,tomorrow\n" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("invalid expires_at: tomorrow")
      expect(preview_row(temp.primary_email)).to be_nil
      expect(response.body).not_to include(I18n.t("directory.import.preview.apply_button"))
    end
  end

  describe "POST /directory/import" do
    it "applies a valid expiry" do
      post directory_import_path, params: { csv_text: "#{temp.primary_email},temps,2099-01-01T12:30:00-05:00\n" }

      expect(response).to redirect_to(directory_root_path)
      membership = Directory::Membership.find_by!(collection: group, member_person: Directory::Person.find_by!(identity: temp))
      expect(membership.expires_at).to eq(Time.utc(2099, 1, 1, 17, 30))
    end

    it "refuses an unparseable expiry instead of granting permanent access" do
      post directory_import_path, params: { csv_text: "#{temp.primary_email},temps,tomorrow\n" }

      expect(response).to redirect_to(directory_new_import_path)
      expect(flash[:alert]).to eq(I18n.t("directory.import.errors", count: 1))
      expect(Directory::Membership.where(collection: group)).to be_empty
    end
  end
end
