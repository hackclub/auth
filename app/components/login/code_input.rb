# frozen_string_literal: true

class Components::Login::CodeInput < Components::Base
  def initialize(form:, field_name: :code, prefix: "H", placeholder: "XXX-XXX", alpine_model: "codeValue", input_id: nil)
    @form = form
    @field_name = field_name
    @prefix = prefix
    @placeholder = placeholder
    @alpine_model = alpine_model
    @input_id = input_id || "code-input-#{field_name}"
  end

  def view_template
    div(class: "code-input-container", onclick: safe("document.getElementById('#{@input_id}').focus()")) do
      span(class: "code-prefix") { @prefix }
      raw @form.text_field @field_name,
        required: true,
        inputmode: "numeric",
        pattern: "[0-9\\-]*",
        autofocus: true,
        autocomplete: "one-time-code",
        maxlength: 7,
        placeholder: @placeholder,
        class: "code-input",
        id: @input_id,
        "x-model": @alpine_model,
        data: { behavior: "otp" }
    end
  end
end

