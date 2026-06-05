# frozen_string_literal: true

module Backend
  class PersonaDashboardController < ApplicationController
    hint :back_navigation, on: :show

    def show
      add_breadcrumb "PERSONA"
      set_keyboard_shortcut(:back, backend_root_path)
      authorize Verification

      @time_period = params[:time_period] || "this_month"
      @start_date = case @time_period
      when "today"      then Time.current.beginning_of_day
      when "this_week"  then Time.current.beginning_of_week
      when "this_month" then Time.current.beginning_of_month
      when "all_time"   then Time.at(0)
      end

      persona_types = %w[Verification::PersonaVerification Verification::PersonaStudentIdVerification]
      @verifications = Verification.not_ignored
        .where(type: persona_types)
        .where("verifications.created_at >= ?", @start_date)

      @stats = calculate_stats
      @prev_stats = calculate_prev_period_stats
      @outcome_breakdown = calculate_outcome_breakdown
      @type_split = calculate_type_split
      @time_buckets = calculate_time_buckets
      @pending_age = calculate_pending_age
      @funnel = calculate_funnel
      @resubmission = calculate_resubmission_rate
      @rejection_breakdown = calculate_rejection_breakdown
      @by_country = calculate_by_country
      @api_errors = calculate_api_errors
    end

    private

    def prev_start_date
      duration = @start_date ? Time.current - @start_date : 0
      @start_date - duration
    end

    def calculate_stats
      total = @verifications.count
      approved = @verifications.approved.count
      rejected = @verifications.rejected.count
      pending = @verifications.pending.count
      draft = @verifications.where(status: "draft").count
      resolved = approved + rejected

      {
        total: total,
        approved: approved,
        rejected: rejected,
        pending: pending,
        draft: draft,
        approval_rate: resolved > 0 ? (approved.to_f / resolved * 100).round(1) : 0
      }
    end

    def calculate_prev_period_stats
      return nil if @time_period == "all_time"

      persona_types = %w[Verification::PersonaVerification Verification::PersonaStudentIdVerification]
      prev = Verification.not_ignored
        .where(type: persona_types)
        .where("verifications.created_at >= ? AND verifications.created_at < ?", prev_start_date, @start_date)

      total = prev.count
      approved = prev.approved.count
      rejected = prev.rejected.count
      resolved = approved + rejected

      {
        total: total,
        approved: approved,
        rejected: rejected,
        approval_rate: resolved > 0 ? (approved.to_f / resolved * 100).round(1) : 0
      }
    end

    def calculate_outcome_breakdown
      approved_ids = @verifications.approved.pluck(:id)

      auto_approved = PublicActivity::Activity
        .where(key: "verification_persona_verification.auto_approve", trackable_id: approved_ids, trackable_type: "Verification")
        .distinct.count(:trackable_id)

      manual_approved = approved_ids.size - auto_approved
      diverted_pending = @verifications.pending.count
      rejected_soft = @verifications.rejected.where(fatal: false).count
      rejected_fatal = @verifications.rejected.where(fatal: true).count

      {
        auto_approved: auto_approved,
        manual_approved: manual_approved,
        diverted_pending: diverted_pending,
        rejected_soft: rejected_soft,
        rejected_fatal: rejected_fatal,
        diversion_rate: @stats[:total] > 0 ?
          ((manual_approved + diverted_pending).to_f / @stats[:total] * 100).round(1) : 0
      }
    end

    def calculate_time_buckets
      resolved = @verifications.where(status: %w[approved rejected]).where.not(pending_at: nil)
      buckets = { "< 5 min" => 0, "5–30 min" => 0, "30 min – 1 hr" => 0, "1–24 hr" => 0, "24 hr+" => 0 }

      resolved.find_each do |v|
        end_time = v.approved_at || v.rejected_at
        next unless end_time
        seconds = end_time - v.pending_at

        key = if seconds < 5.minutes
          "< 5 min"
        elsif seconds < 30.minutes
          "5–30 min"
        elsif seconds < 1.hour
          "30 min – 1 hr"
        elsif seconds < 24.hours
          "1–24 hr"
        else
          "24 hr+"
        end

        buckets[key] += 1
      end

      buckets
    end

    def calculate_funnel
      started = @verifications.count
      completed = @verifications.where(status: %w[pending approved rejected]).count
      approved = @verifications.approved.count

      {
        started: started,
        completed: completed,
        approved: approved,
        start_to_complete: started > 0 ? (completed.to_f / started * 100).round(1) : 0,
        complete_to_approved: completed > 0 ? (approved.to_f / completed * 100).round(1) : 0
      }
    end

    def calculate_resubmission_rate
      identity_ids = @verifications.distinct.pluck(:identity_id)
      return { total_people: 0, first_try: 0, multiple_tries: 0, rate: 0 } if identity_ids.empty?

      counts = @verifications.where(identity_id: identity_ids).group(:identity_id).count
      first_try = counts.count { |_, c| c == 1 }
      multiple = counts.count { |_, c| c > 1 }

      {
        total_people: counts.size,
        first_try: first_try,
        multiple_tries: multiple,
        rate: counts.size > 0 ? (multiple.to_f / counts.size * 100).round(1) : 0
      }
    end

    def calculate_rejection_breakdown
      rejected = @verifications.rejected
      return {} if rejected.empty?

      breakdown = {}
      rejected.each do |v|
        next unless v.rejection_reason.present?
        name = v.try(:rejection_reason_name) || v.rejection_reason.humanize
        breakdown[name] ||= { count: 0, fatal: v.fatal? }
        breakdown[name][:count] += 1
      end

      breakdown.sort_by { |_, d| -d[:count] }.to_h
    end

    def calculate_type_split
      gov_id = @verifications.where(type: "Verification::PersonaVerification")
      student_id = @verifications.where(type: "Verification::PersonaStudentIdVerification")

      {
        gov_id: {
          total: gov_id.count,
          approved: gov_id.approved.count,
          rejected: gov_id.rejected.count,
          pending: gov_id.pending.count
        },
        student_id: {
          total: student_id.count,
          approved: student_id.approved.count,
          rejected: student_id.rejected.count,
          pending: student_id.pending.count
        }
      }
    end

    def calculate_pending_age
      pending = @verifications.pending.order(:pending_at)
      return nil if pending.empty?

      ages = pending.pluck(:pending_at).compact.map { |t| Time.current - t }
      {
        count: ages.size,
        oldest: ages.max,
        median: ages.sort[ages.size / 2],
        newest: ages.min
      }
    end

    def calculate_by_country
      by_country = {}

      @verifications.includes(:identity).find_each do |v|
        country_code = v.identity&.country
        next unless country_code.present?

        by_country[country_code] ||= { approved: 0, rejected: 0, pending: 0, draft: 0, total: 0 }
        by_country[country_code][:total] += 1

        case v.status
        when "approved" then by_country[country_code][:approved] += 1
        when "rejected" then by_country[country_code][:rejected] += 1
        when "pending"  then by_country[country_code][:pending] += 1
        when "draft"    then by_country[country_code][:draft] += 1
        end
      end

      by_country.map do |code, data|
        resolved = data[:approved] + data[:rejected]
        name = ISO3166::Country[code]&.common_name || code
        [name, data.merge(
          approval_rate: resolved > 0 ? (data[:approved].to_f / resolved * 100).round(1) : nil
        )]
      end.sort_by { |_, d| -d[:total] }.to_h
    end

    def calculate_api_errors
      persona_jobs = %w[
        Persona::ProcessInquiryEventJob
        Persona::VerificationPipelineJob
      ]

      failed = GoodJob::Job
        .where(job_class: persona_jobs)
        .where("created_at >= ?", @start_date)
        .where.not(error: nil)

      by_class = failed.group(:job_class).count
      recent = failed.order(created_at: :desc).limit(5).pluck(:job_class, :error, :created_at)

      {
        total: failed.count,
        by_class: by_class,
        recent: recent.map { |cls, err, at| { job: cls.demodulize, error: err.to_s.truncate(120), at: at } }
      }
    end
  end
end
