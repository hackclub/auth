require "rails_helper"

RSpec.describe VerificationCase::SendLinkReminderJob, type: :job do
  include ActiveJob::TestHelper

  def quiet_case(**attrs)
    create(:verification_case, :link_sent, link_sent_at: 4.days.ago, **attrs)
  end

  it "reminds a quiet case with a fresh link and logs it" do
    kase = quiet_case
    old_token = kase.access_token

    expect { described_class.perform_now }
      .to have_enqueued_mail(VerificationCaseMailer, :reminder).once

    kase.reload
    expect(kase.access_token).not_to eq(old_token)
    expect(kase.access_token_used_at).to be_nil
    expect(kase).to be_link_sent
    expect(kase.events.where(key: "reminder_sent").count).to eq(1)
  end

  it "only reminds once" do
    quiet_case

    described_class.perform_now
    expect { described_class.perform_now }
      .not_to have_enqueued_mail(VerificationCaseMailer, :reminder)
  end

  it "skips cases whose link went out recently" do
    create(:verification_case, :link_sent, link_sent_at: 1.day.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(VerificationCaseMailer, :reminder)
  end

  it "skips cases that have moved past link_sent" do
    create(:verification_case, :docs_submitted, link_sent_at: 4.days.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(VerificationCaseMailer, :reminder)
  end

  it "skips cases whose token has already expired" do
    quiet_case(access_token_expires_at: 1.hour.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(VerificationCaseMailer, :reminder)
  end
end
