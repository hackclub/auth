FactoryBot.define do
  factory :address do
    association :identity
    first_name { "Helena" }
    last_name { "Ackfoundation" }
    line_1 { "8605 Santa Monica Blvd" }
    line_2 { "PMB 86294" }
    city { "West Hollywood" }
    state { "CA" }
    postal_code { "90069" }
    country { "US" }
  end
end
