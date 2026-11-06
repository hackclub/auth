# frozen_string_literal: true

RSpec.configure do |config|
  config.after(:each) do
    Persona.reset!
    SAMLService::Entities.reset!
    WebMock.allow_net_connect! if defined?(WebMock)
  end

  config.after(:each) do
    Flipper.features.each { |f| f.disable rescue nil }
  end
end
