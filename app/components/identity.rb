# frozen_string_literal: true

class Components::Identity < Components::Base
  attr_reader :identity

  def initialize(identity, show_legal_name: false)
    @identity = identity
    @show_legal_name = show_legal_name
  end

  def view_template
    div class: "identity-details" do
      render @identity

      if @identity.legal_first_name.present? && @show_legal_name
        detail_row("legal name", "#{@identity.legal_first_name} #{@identity.legal_last_name}")
      end
      detail_row("country", @identity.country)
      detail_row("email", @identity.primary_email)
      detail_row("birthday", @identity.birthday)
      detail_row("phone", @identity.phone_number)
      detail_row("status", @identity.verification_status.humanize)

      if defined?(@identity.ysws_eligible) && !@identity.ysws_eligible.nil?
        detail_row("ysws", @identity.ysws_eligible ? "eligible" : "ineligible")
      end

      detail_row("slack") do
        if identity.slack_id.present?
          a(href: "https://hackclub.slack.com/team/#{identity.slack_id}") { identity.slack_id }
        else
          i { "not set" }
        end
      end
    end
  end

  private

  def detail_row(label, value = nil, &block)
    div class: "detail-row" do
      span(class: "detail-label") { label }
      span class: "detail-value" do
        if block_given?
          yield
        else
          plain value.to_s
        end
      end
    end
  end
end
