# frozen_string_literal: true

class AnalyticsService
  SIGNUP_FUNNEL_EVENTS = %w[
    signup.started
    signup.completed
  ].freeze

  SIGNUP_REJECTION_EVENTS = %w[
    signup.age_rejected
    signup.validation_failed
    signup.existing_account
  ].freeze

  LOGIN_FUNNEL_EVENTS = %w[
    login.code_sent
    login.code_verified
    login.completed
  ].freeze

  def initialize(start_date:, end_date:, scenario: nil)
    @start_date = start_date
    @end_date = end_date
    @scenario = scenario
  end

  # Signup funnel: started -> completed
  def signup_funnel
    base_scope = events_in_range.signup

    SIGNUP_FUNNEL_EVENTS.each_with_object({}) do |event, result|
      scope = base_scope.by_name(event)
      scope = scope.by_scenario(@scenario) if @scenario
      result[event] = scope.count
    end
  end

  # Signup conversion rate
  def signup_conversion_rate
    funnel = signup_funnel
    started = funnel["signup.started"].to_f
    completed = funnel["signup.completed"].to_f

    return 0 if started.zero?
    ((completed / started) * 100).round(2)
  end

  # Rejection breakdown
  def rejection_breakdown
    result = {}

    # Age rejections by type
    age_rejections = events_in_range
      .by_name("signup.age_rejected")
      .group("properties->>'rejection_type'")
      .count

    result[:age_rejections] = {
      too_old: age_rejections["too_old"] || 0,
      under_13: age_rejections["under_13"] || 0
    }

    # Validation errors
    result[:validation_errors] = events_in_range.by_name("signup.validation_failed").count

    # Existing accounts
    result[:existing_accounts] = events_in_range.by_name("signup.existing_account").count

    result
  end

  # Login funnel: code_sent -> completed
  def login_funnel
    LOGIN_FUNNEL_EVENTS.each_with_object({}) do |event, result|
      result[event] = events_in_range.by_name(event).count
    end
  end

  # Dialogue funnel
  def dialogue_funnel
    {
      first_interaction: events_in_range.by_name("dialogue.first_interaction").count,
      promoted: events_in_range.by_name("dialogue.promoted").count
    }
  end

  # Scenario comparison
  def scenario_comparison
    events_in_range
      .by_name("signup.completed")
      .group("properties->>'scenario'")
      .count
      .sort_by { |_, v| -v }
      .to_h
  end

  # Country breakdown
  def country_breakdown
    events_in_range
      .by_name("signup.started")
      .group("properties->>'country'")
      .count
      .sort_by { |_, v| -v }
      .to_h
  end

  # Daily trends for charting
  def daily_trends(event_name)
    events_in_range
      .by_name(event_name)
      .group_by_day(:time)
      .count
  end

  # Overview stats
  def overview
    {
      total_signups_started: events_in_range.by_name("signup.started").count,
      total_signups_completed: events_in_range.by_name("signup.completed").count,
      total_logins_completed: events_in_range.by_name("login.completed").count,
      total_verifications: events_in_range.by_name("verification.submitted").count,
      total_addresses: events_in_range.by_name("address.created").count,
      dialogue_promotions: events_in_range.by_name("dialogue.promoted").count,
      conversion_rate: signup_conversion_rate
    }
  end

  private

  def events_in_range
    Ahoy::Event.in_range(@start_date, @end_date)
  end
end
