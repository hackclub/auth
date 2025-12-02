FactoryBot.define do
  factory :oauth_token do
    association :resource_owner, factory: :identity
    association :application, factory: :program
    token { OAuthToken.generate }
    scopes { "basic_info" }
    expires_in { nil }
    revoked_at { nil }

    trait :with_all_scopes do
      scopes { "verification_status basic_info email name slack_id legal_name address" }
    end

    trait :expired do
      expires_in { -1 }
    end

    trait :revoked do
      revoked_at { 1.hour.ago }
    end
  end
end
