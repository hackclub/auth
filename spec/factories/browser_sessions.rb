FactoryBot.define do
  factory :browser_session do
    token { SecureRandom.urlsafe_base64 }
    expires_at { 1.month.from_now }

    trait :expired do
      expires_at { 1.hour.ago }
    end

    # Builds a browser session holding one signed-in account.
    transient do
      identity { nil }
    end

    trait :with_account do
      after(:create) do |browser_session, evaluator|
        identity = evaluator.identity || create(:identity)
        ident_session = create(:identity_session, identity: identity, browser_session: browser_session)
        browser_session.activate!(ident_session)
      end
    end
  end
end
