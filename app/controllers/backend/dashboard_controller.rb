# frozen_string_literal: true

module Backend
  class DashboardController < ApplicationController
    # i really hope any of this math is right!

    hint :back_navigation, on: :show

    def show
      set_keyboard_shortcut(:back, backend_root_path)
      authorize Verification

      @time_period = params[:time_period] || "this_month"
      @start_date = case @time_period
      when "today"
          Time.current.beginning_of_day
      when "this_month"
          Time.current.beginning_of_month
      when "all_time"
          Time.at(0)
      end

      @verifications = Verification.not_ignored.where("created_at >= ?", @start_date)

      @stats = {
        total: @verifications.count,
        approved: @verifications.approved.count,
        rejected: @verifications.rejected.count,
        pending: @verifications.pending.count,
        average_hangtime: calculate_average_hangtime(@verifications)
      }

      # Calculate rejection reason breakdown
      @rejection_breakdown = calculate_rejection_breakdown(@verifications.rejected)

      # Calculate rejections by country
      @rejections_by_country = calculate_rejections_by_country(@verifications.rejected)

      # Get leaderboard data
      activity_counts = PublicActivity::Activity
        .where(key: [ "verification.approve", "verification.reject" ])
        .where("activities.created_at >= ?", @start_date)
        .where.not(owner_id: nil)
        .group(:owner_id)
        .count
        .sort_by { |_, count| -count }

      user_ids = activity_counts.map(&:first)
      users = Backend::User.where(id: user_ids).index_by(&:id)

      @leaderboard = activity_counts.map do |user_id, count|
        {
          user: users[user_id],
          processed_count: count
        }
      end
    end

    private

    def calculate_average_hangtime(verifications)
      return "0 seconds" if verifications.empty?

      total_seconds = verifications.sum do |verification|
        start_time = verification.pending_at || verification.created_at
        end_time = verification.approved_at || verification.rejected_at || (verification.updated_at if verification.approved? || verification.rejected?) || Time.now

        end_time - start_time
      end

      total_seconds / verifications.count
    end

    # this should be less bad
    def calculate_rejection_breakdown(rejected_verifications)
      return {} if rejected_verifications.empty?

      breakdown = {}

      rejected_verifications.each do |verification|
        next unless verification.rejection_reason.present?

        is_fatal = case verification.class.name
        when "Verification::DocumentVerification"
            Verification::DocumentVerification::FATAL_REJECTION_REASONS.include?(verification.rejection_reason)
        when "Verification::AadhaarVerification"
            Verification::AadhaarVerification::FATAL_REJECTION_REASONS.include?(verification.rejection_reason)
        else
            false
        end

        reason_name = verification.try(:rejection_reason_name) || verification.rejection_reason.humanize

        breakdown[reason_name] ||= { count: 0, fatal: is_fatal }
        breakdown[reason_name][:count] += 1
      end

      breakdown.sort_by { |_, data| -data[:count] }.to_h
    end

    def calculate_rejections_by_country(rejected_verifications)
      return {} if rejected_verifications.empty?

      by_country = {}

      rejected_verifications.includes(:identity).each do |verification|
        next unless verification.rejection_reason.present?
        next unless verification.identity&.country.present?

        country_code = verification.identity.country
        country_name = ISO3166::Country[country_code]&.common_name || country_code

        by_country[country_name] ||= { total: 0, fatal: 0, reasons: {} }
        by_country[country_name][:total] += 1
        by_country[country_name][:fatal] += 1 if verification.fatal?

        reason_name = verification.try(:rejection_reason_name) || verification.rejection_reason.humanize
        by_country[country_name][:reasons][reason_name] ||= { count: 0, fatal: verification.fatal? }
        by_country[country_name][:reasons][reason_name][:count] += 1
      end

      # Calculate fraud rate and sort by fatal count (most suspicious first)
      by_country.transform_values do |data|
        data[:reasons] = data[:reasons].sort_by { |_, r| [ r[:fatal] ? 0 : 1, -r[:count] ] }.to_h
        data[:fatal_rate] = data[:total] > 0 ? (data[:fatal].to_f / data[:total] * 100).round(1) : 0
        data
      end.sort_by { |_, data| [ -data[:fatal], -data[:total] ] }.to_h
    end
  end
end
