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

  # Helper to get scenario from an identity's signup scenario
  def analytics_scenario_for(identity)
    identity&.onboarding_scenario_instance&.class&.slug
  end

  # Helper to get program from a return_to URL containing OAuth client_id
  def program_from_return_to(return_to)
    return nil if return_to.blank?

    uri = URI.parse(return_to)
    params = URI.decode_www_form(uri.query || "").to_h
    client_id = params["client_id"]
    Program.find_by(uid: client_id) if client_id.present?
  rescue URI::InvalidURIError
    nil
  end

  # Helper to get scenario from the program in a return_to URL
  def analytics_scenario_from_return_to(return_to)
    program_from_return_to(return_to)&.onboarding_scenario
  end
end
