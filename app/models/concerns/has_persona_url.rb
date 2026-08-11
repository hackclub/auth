module HasPersonaUrl
  extend ActiveSupport::Concern

  included do
    def self.has_persona_url(resource, id_field)
      define_method(:persona_dashboard_url) do
        id = try(id_field)
        return if id.nil?

        "https://app.withpersona.com/dashboard/#{resource}/#{id}"
      end
    end
  end
end
