# frozen_string_literal: true

RSpec.configure do |config|
  config.after(:each) do
    Persona.reset!
    SAMLService::Entities.reset!
  end

  config.after(:each) do
    Flipper.features.each(&:disable)
  end
end
