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

  # the user opened the link on day 0 and stalled mid-capture: their session
  # is live, and a rotated link would lock them out
  it "leaves a case alone once the link has been opened" do
    kase = quiet_case(access_token_used_at: 3.days.ago)
    token = kase.access_token

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(VerificationCaseMailer, :reminder)

    kase.reload
    expect(kase.access_token).to eq(token)
    expect(kase.access_token_used_at).to be_present
    expect(kase.events.where(key: "reminder_sent")).not_to exist
  end

  it "does not rotate a link that gets opened between the query and the nudge" do
    kase = quiet_case
    token = kase.access_token
    allow(VerificationCase).to receive(:due_for_link_reminder).and_wrap_original do |m, **kw|
      relation = m.call(**kw)
      kase.consume_access_token!(token)
      relation
    end

    expect { described_class.perform_now }
      .not_to have_enqueued_mail(VerificationCaseMailer, :reminder)

    kase.reload
    expect(kase.access_token).to eq(token)
    expect(kase.access_token_used_at).to be_present
  end
end
