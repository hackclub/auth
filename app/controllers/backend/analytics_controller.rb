# frozen_string_literal: true

module Backend
  class AnalyticsController < ApplicationController
    def show
      authorize :analytics, :show?

      @time_period = params[:time_period] || "this_month"
      @start_date, @end_date = date_range_for(@time_period)

      @analytics = AnalyticsService.new(
        start_date: @start_date,
        end_date: @end_date
      )

      @overview = @analytics.overview
      @signup_funnel = @analytics.signup_funnel
      @rejection_breakdown = @analytics.rejection_breakdown
      @login_funnel = @analytics.login_funnel
      @dialogue_funnel = @analytics.dialogue_funnel
      @scenario_comparison = @analytics.scenario_comparison
      @country_breakdown = @analytics.country_breakdown.first(10).to_h

      # Daily trends for charts
      @signup_trends = @analytics.daily_trends("signup.completed")
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
