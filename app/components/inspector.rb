# frozen_string_literal: true

class Components::Inspector < Components::Base
  def initialize(record, small: false)
    @record = record
    @small = small
  end

  def view_template
    return unless Rails.env.development?

    details class: "inspector" do
      summary do
        if @small
          plain record_id
        else
          plain "inspect #{record_id}"
        end
      end
      pre class: "inspector-content" do
        unless @record.nil?
          raw safe(ap @record)
        else
          plain "nil"
        end
      end
    end
  end

  private

  def record_id
    "#{@record.class.name} #{@record&.try(:public_id) || @record&.id}"
  end
end
