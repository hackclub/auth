# frozen_string_literal: true

class Components::Resemblance < Components::Base
  attr_reader :resemblance

  def initialize(resemblance)
    @resemblance = resemblance
  end

  def view_template
    div class: "lowered resemblance" do
      div class: "section" do
        div(class: "section-header") { h3 { resemblance_title } }
        div class: "section-content" do
          render @resemblance
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

  def resemblance_title
    case @resemblance
    when Identity::Resemblance::NameResemblance
      "name match"
    when Identity::Resemblance::ReusedDocumentResemblance
      "document reuse"
    when Identity::Resemblance::EmailSubaddressResemblance
      "email subaddressing"
    else
      "resemblance"
    end
  end
end
