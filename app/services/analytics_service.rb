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

  # Complete user journey for program operators
  PROGRAM_FUNNEL_EVENTS = %w[
    signup.started
    login.code_sent
    signup.completed
    login.completed
    oauth.authorized
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
    scope = events_in_range.by_name("signup.age_rejected")
    scope = scope.by_scenario(@scenario) if @scenario
    age_rejections = scope.group("properties->>'rejection_type'").count

    result[:age_rejections] = {
      too_old: age_rejections["too_old"] || 0,
      under_13: age_rejections["under_13"] || 0
    }

    # Validation errors
    validation_scope = events_in_range.by_name("signup.validation_failed")
    validation_scope = validation_scope.by_scenario(@scenario) if @scenario
    result[:validation_errors] = validation_scope.count

    # Existing accounts
    existing_scope = events_in_range.by_name("signup.existing_account")
    existing_scope = existing_scope.by_scenario(@scenario) if @scenario
    result[:existing_accounts] = existing_scope.count

    result
  end

  # Login funnel: code_sent -> completed
  def login_funnel
    LOGIN_FUNNEL_EVENTS.each_with_object({}) do |event, result|
      scope = events_in_range.by_name(event)
      scope = scope.by_scenario(@scenario) if @scenario
      result[event] = scope.count
    end
  end

  # Dialogue funnel
  def dialogue_funnel
    first_scope = events_in_range.by_name("dialogue.first_interaction")
    first_scope = first_scope.by_scenario(@scenario) if @scenario

    promoted_scope = events_in_range.by_name("dialogue.promoted")
    promoted_scope = promoted_scope.by_scenario(@scenario) if @scenario

    {
      first_interaction: first_scope.count,
      promoted: promoted_scope.count
    }
  end

  # OAuth funnel
  def oauth_funnel
    {
      authorized: scoped_count("oauth.authorized"),
      denied: scoped_count("oauth.denied"),
      revoked: scoped_count("oauth.revoked")
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
    scope = events_in_range.by_name("signup.started")
    scope = scope.by_scenario(@scenario) if @scenario
    scope
      .group("properties->>'country'")
      .count
      .sort_by { |_, v| -v }
      .to_h
  end

  # Daily trends for charting
  def daily_trends(event_name)
    scope = events_in_range.by_name(event_name)
    scope = scope.by_scenario(@scenario) if @scenario
    scope.group_by_day(:time).count
  end

  # Overview stats - when filtering by scenario, show program-centric metrics
  def overview
    if @scenario
      # Program-centric view: what matters is users delivered to the program
      started = scoped_count("signup.started") + scoped_count("login.code_sent")
      authorized = scoped_count("oauth.authorized")
      conversion = started > 0 ? ((authorized.to_f / started) * 100).round(2) : 0

      {
        visitors: started,
        new_signups: scoped_count("signup.completed"),
        returning_logins: scoped_count("login.completed"),
        authorized: authorized,
        denied: scoped_count("oauth.denied"),
        conversion_rate: conversion
      }
    else
      # Global view: overall platform health
      {
        total_signups_started: scoped_count("signup.started"),
        total_signups_completed: scoped_count("signup.completed"),
        total_logins_completed: scoped_count("login.completed"),
        total_oauth_authorized: scoped_count("oauth.authorized"),
        total_verifications: scoped_count("verification.submitted"),
        slack_provisioned: scoped_count("slack.provisioned"),
        conversion_rate: signup_conversion_rate
      }
    end
  end

  # Program funnel: full journey from arrival to authorization
  def program_funnel
    {
      started: scoped_count("signup.started") + scoped_count("login.code_sent"),
      authenticated: scoped_count("signup.completed") + scoped_count("login.completed"),
      authorized: scoped_count("oauth.authorized"),
      denied: scoped_count("oauth.denied")
    }
  end

  private

  def events_in_range
    Ahoy::Event.in_range(@start_date, @end_date)
  end

  def scoped_count(event_name)
    scope = events_in_range.by_name(event_name)
    scope = scope.by_scenario(@scenario) if @scenario
    scope.count
  end
end
