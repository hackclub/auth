class Components::Inspector < Components::Base
  def initialize(record, small: false)
    @record = record
    @small = small
    @id_line = "#{@record.class.name}#{" record" unless @small} #{@record&.try(:public_id) || @record&.id}"
  end

  def view_template
    return unless Rails.env.development?

    details(class: @small ? nil : "dev-tool") do
      summary { "#{"Inspect" unless @small} #{@id_line}" }
      pre class: %i[input readonly] do
        unless @record.nil?
          raw safe(ap @record)
        else
          "no record?"
        end
      end
    end
  end
end
