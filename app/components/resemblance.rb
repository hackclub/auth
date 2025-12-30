# frozen_string_literal: true

class Components::Resemblance < Components::Base
  include Phlex::Rails::Helpers::Routes

  attr_reader :resemblance

  def initialize(resemblance)
    @resemblance = resemblance
  end

  def view_template
    div class: "lowered resemblance" do
      div class: "section" do
        div(class: "section-header") { h3 { @resemblance.title } }
        div class: "section-content" do
          detail_row("this identity", @resemblance.current_label)
          detail_row("matches") do
            a(href: backend_identity_path(@resemblance.past_identity), target: "_blank") { @resemblance.matched_label }
            if @resemblance.matched_verification
              plain " ("
              a(href: backend_verification_path(@resemblance.matched_verification), target: "_blank") { "verification" }
              plain ")"
            end
          end
        end
      end
      div class: "section" do
        div(class: "section-header") { h3 { "matched identity" } }
        div class: "section-content" do
          render Components::Identity.new(@resemblance.past_identity)
        end
      end
      render Components::Inspector.new(@resemblance)
    end
  end

  private

  def detail_row(label, value = nil, &block)
    div class: "detail-row" do
      span(class: "detail-label") { label }
      span(class: "detail-value") { block ? yield : value }
    end
  end
end
