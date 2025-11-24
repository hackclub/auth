class Components::AuthWelcomeTest < Components::Base
  def initialize(service_name: nil, return_to: nil)
    @service_name = service_name
    @return_to = return_to
  end

  def view_template
    div(class: "auth-container") do
      h1 { "Test: #{@service_name}" }
      p { "Return to: #{@return_to}" }
    end
  end
end
