# frozen_string_literal: true

class Components::Backend::IdentityPicker < Components::Base
  def initialize(
    name: nil,
    selected: nil,
    multiple: false,
    required: false,
    placeholder: nil
  )
    @name = name || (multiple ? "identity_ids" : "identity_id")
    @selected = multiple ? Array(selected) : selected
    @multiple = multiple
    @required = required
    @placeholder = placeholder || (multiple ? "Search to add..." : "Search identities...")
  end

  def view_template
    div(data_identity_picker: true) do
      script(type: "application/json", class: "picker-initial-data") do
        raw safe picker_config.to_json
      end
    end
  end

  private

  def picker_config
    {
      name: @name,
      multiple: @multiple,
      required: @required,
      placeholder: @placeholder,
      selected: format_selected
    }
  end

  def format_selected
    if @multiple
      Array(@selected).map { |identity| format_identity(identity) }
    else
      @selected ? format_identity(@selected) : nil
    end
  end

  def format_identity(identity)
    case identity
    when Identity
      {
        id: identity.public_id,
        label: identity.full_name,
        sublabel: identity.primary_email
      }
    when Hash
      identity.slice(:id, :label, :sublabel).transform_keys(&:to_sym)
    else
      { id: identity.to_s, label: identity.to_s, sublabel: nil }
    end
  end
end
