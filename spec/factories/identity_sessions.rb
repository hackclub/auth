FactoryBot.define do
  factory :identity_session do
    association :identity
    session_token { SecureRandom.urlsafe_base64 }
    expires_at { 1.month.from_now }

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :stepped_up do
      last_step_up_at { Time.current }
      last_step_up_action { "oidc_reauth" }
    end
  end
end
