# frozen_string_literal: true

class Components::Resemblance < Components::Base
  attr_reader :resemblance

  def initialize(resemblance)
    @resemblance = resemblance
  end

  def view_template
    div class: "lowered" do
      render @resemblance
      div class: "section" do
        div(class: "section-header") { h3 { "matched identity" } }
        div class: "section-content" do
          render Components::Identity.new(@resemblance.past_identity)
        end
      end
      render Components::Inspector.new(@resemblance)
    end
  end
end
