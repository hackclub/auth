# frozen_string_literal: true

module AhoyAnalytics
  extend ActiveSupport::Concern

  private

  def track_event(name, properties = {})
    return unless analytics_enabled?

    ahoy.track(name, properties)
  rescue => e
    Rails.logger.warn("Analytics tracking failed: #{e.message}")
  end

  def analytics_enabled?
    return false if ENV["DISABLE_ANALYTICS"] == "true"

    true
  end

  # Helper to get scenario slug safely from @onboarding_scenario
  def analytics_scenario
    @onboarding_scenario&.class&.slug
  end

  # Helper to get scenario from an identity
  def analytics_scenario_for(identity)
    identity&.onboarding_scenario_instance&.class&.slug
  end
end
