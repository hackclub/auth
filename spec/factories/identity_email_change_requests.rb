FactoryBot.define do
  factory :email_change_request, class: "Identity::EmailChangeRequest" do
    identity
    sequence(:new_email) { |n| "new#{n}@example.com" }
    old_email { identity&.primary_email || "old@example.com" }
    expires_at { 24.hours.from_now }

    trait :with_tokens do
      after(:create) do |request|
        request.generate_tokens!
      end
    end

    trait :old_verified do
      old_email_verified_at { Time.current }
    end

    trait :new_verified do
      new_email_verified_at { Time.current }
    end

    trait :both_verified do
      old_email_verified_at { Time.current }
      new_email_verified_at { Time.current }
    end

    trait :completed do
      old_email_verified_at { 1.hour.ago }
      new_email_verified_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :cancelled do
      cancelled_at { Time.current }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end
  end
end
