# frozen_string_literal: true

class Components::BreakTheGlassForm < Components::Base
  def initialize(break_glassable)
    @break_glassable = break_glassable
  end

  def view_template
    div(class: "break-glass-form", style: "padding: 2rem;") do
      div(style: "margin-bottom: 1rem;") do
        vite_image_tag "images/icons/break-the-glass.png", style: "width: 64px; image-rendering: pixelated;"
        div(style: "display: inline-block; vertical-align: top; margin-left: 0.5em;") do
          h1(style: "margin 0; display: inline-block; vertical-align: top;") { "Break the Glass" }
          br
          plain "This #{document_type} has already been reviewed."
          br
          plain "Please affirm that you have a legitimate need to view this #{document_type}."
        end
      end

      form_with url: "/backend/break_glass", method: :post, local: true, style: "max-width: 400px; margin: 0 auto;" do |form|
        form.hidden_field :break_glassable_id, value: @break_glassable.id
        form.hidden_field :break_glassable_type, value: @break_glassable.class.name

        div(style: "display: flex; align-items: center; gap: 0.5em;") do
          p { "I'm accessing this #{document_type} " }
          form.text_field :reason, placeholder: "because i'm investigating a fraud claim", style: "width: 30%;"
          form.submit "i promise.", class: "button button-primary"
        end
      end
    end
  end

  private

  def document_type
    case @break_glassable.class.name
    when "Identity::Document"
      "identity document"
    when "Identity::AadhaarRecord"
      "aadhaar record"
    else
      "document"
    end
  end
end
