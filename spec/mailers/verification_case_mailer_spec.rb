require "rails_helper"

RSpec.describe VerificationCaseMailer, type: :mailer do
  # the mailer layout builds an absolute asset url through the route helpers,
  # which don't pick up action_mailer.default_url_options in test
  around do |example|
    previous = Rails.application.routes.default_url_options[:host]
    Rails.application.routes.default_url_options[:host] = "example.com"
    example.run
  ensure
    Rails.application.routes.default_url_options[:host] = previous
  end

  describe "#reminder" do
    it "carries a fresh single-use link and its expiry" do
      kase = create(:verification_case, :link_sent, identity: create(:identity, first_name: "Pat"))
      token = kase.generate_access_token!

      mail = described_class.reminder(kase, token)

      expect(mail.to).to eq([ kase.identity.primary_email ])
      expect(mail.subject).to include("Reminder")
      [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
        expect(body).to include("Hey Pat")
        expect(body).to include("token=#{token}")
        expect(body).to include(kase.access_token_expires_at.strftime("%B %-d, %Y"))
      end
    end
  end

  describe "#denied" do
    it "tells the user without relaying the internal rejection reason" do
      kase = create(:verification_case, :call_held, identity: create(:identity, first_name: "Pat"))
      verification = create(:manual_verification_call, identity: kase.identity)
      verification.mark_as_rejected!("fraud", "internal note about mismatched document numbers")
      kase.update!(verification: verification)

      mail = described_class.denied(kase)

      expect(mail.to).to eq([ kase.identity.primary_email ])
      [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
        expect(body).to include("Hey Pat")
        expect(body).to include("weren't able to approve")
        expect(body).not_to include("fraud")
        expect(body).not_to include("mismatched document numbers")
      end
    end
  end

  describe "#redo_requested" do
    it "carries the reviewer's message and a working single-use link" do
      kase = create(:verification_case, :link_sent, identity: create(:identity, first_name: "Pat"))
      token = kase.generate_access_token!

      mail = described_class.redo_requested(kase, token, "the photo is too blurry to read the name")

      expect(mail.to).to eq([ kase.identity.primary_email ])
      expect(mail.subject).to include("resubmit your verification documents")
      [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
        expect(body).to include("Hey Pat")
        expect(body).to include("too blurry to read the name")
        expect(body).to include("token=#{token}")
        expect(body).to include(kase.access_token_expires_at.strftime("%B %-d, %Y"))
      end
    end
  end
end
