class IdentitiesController < ApplicationController
    before_action :set_identity, except: [ :new, :create ]
    before_action :set_onboarding_scenario

    private

    def set_identity
        @identity = current_identity
    end

    def set_onboarding_scenario
        @onboarding_scenario = OnboardingScenarios::DefaultJoin.new(current_identity)
    end
end