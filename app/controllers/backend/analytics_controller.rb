# frozen_string_literal: true

module Backend
  class AnalyticsController < ApplicationController
    def show
      authorize :analytics, :show?

      @time_period = params[:time_period] || "this_month"
      @start_date, @end_date = date_range_for(@time_period)
      @scenario = params[:scenario].presence
      @available_scenarios = OnboardingScenarios::Base.available_slugs

      @analytics = AnalyticsService.new(
        start_date: @start_date,
        end_date: @end_date,
        scenario: @scenario
      )

      @overview = @analytics.overview
      @program_funnel = @analytics.program_funnel if @scenario
      @signup_funnel = @analytics.signup_funnel
      @rejection_breakdown = @analytics.rejection_breakdown
      @login_funnel = @analytics.login_funnel
      @oauth_funnel = @analytics.oauth_funnel
      @dialogue_funnel = @analytics.dialogue_funnel
      @scenario_comparison = @analytics.scenario_comparison unless @scenario
      @country_breakdown = @analytics.country_breakdown.first(10).to_h
      @promotion_breakdown = @analytics.promotion_breakdown

      # Daily trends for charts - show oauth.authorized when filtering by scenario
      if @scenario
        @primary_trends = @analytics.daily_trends("oauth.authorized")
        @primary_trends_label = "authorizations"
      else
        @primary_trends = @analytics.daily_trends("signup.completed")
        @primary_trends_label = "signups"
      end
      @rejection_trends = @analytics.daily_trends("signup.age_rejected")
    end

    private

    def date_range_for(period)
      case period
      when "today"
        [ Time.current.beginning_of_day, Time.current ]
      when "this_week"
        [ Time.current.beginning_of_week, Time.current ]
      when "this_month"
        [ Time.current.beginning_of_month, Time.current ]
      when "last_30_days"
        [ 30.days.ago.beginning_of_day, Time.current ]
      when "all_time"
        [ Time.at(0), Time.current ]
      else
        [ Time.current.beginning_of_month, Time.current ]
      end
    end
  end
end
