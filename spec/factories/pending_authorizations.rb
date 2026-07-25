FactoryBot.define do
  factory :pending_authorization do
    association :browser_session
    token { SecureRandom.urlsafe_base64 }
    kind { "oidc" }
    payload { { "params" => { "client_id" => "abc", "redirect_uri" => "https://example.com/callback" } } }
    expires_at { PendingAuthorization::EXPIRATION.from_now }

    trait :expired do
      expires_at { 1.minute.ago }
    end

    trait :consumed do
      consumed_at { Time.current }
    end

    trait :saml do
      kind { "saml" }
      payload { { "url" => "/saml/auth?SAMLRequest=abc", "entity_id" => "https://sp.example.com" } }
    end
  end
end
