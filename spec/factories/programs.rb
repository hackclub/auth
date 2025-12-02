FactoryBot.define do
  factory :program do
    sequence(:name) { |n| "Test Program #{n}" }
    sequence(:uid) { |n| SecureRandom.hex(16) }
    secret { SecureRandom.hex(32) }
    redirect_uri { "https://example.com/callback" }
    scopes { "basic_info email name" }
    active { true }

    trait :with_all_scopes do
      scopes { "verification_status basic_info email name slack_id legal_name address" }
    end

    trait :inactive do
      active { false }
    end
  end
end
