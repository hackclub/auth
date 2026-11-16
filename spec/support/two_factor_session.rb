# frozen_string_literal: true

# request specs sign in by stubbing current_identity, so there's no login attempt to have
# passed 2FA. treat every session as 2FA'd; specs about the 2FA gate stub it back to false.
RSpec.configure do |config|
  config.before(type: :request) do
    allow_any_instance_of(ApplicationController).to receive(:two_factor_session?).and_return(true)
  end
end
