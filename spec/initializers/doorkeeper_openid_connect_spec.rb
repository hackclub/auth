# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Doorkeeper::OpenidConnect config" do
  # `return` inside these config procs raises LocalJumpError at call time
  it "auth_time is nil, not a LocalJumpError, when the identity has no live session" do
    identity = create(:identity)

    expect(Doorkeeper::OpenidConnect.configuration.auth_time_from_resource_owner.call(identity)).to be_nil
  end
end
