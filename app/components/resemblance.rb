class Components::Resemblance < Components::Base
  attr_reader :resemblance

  def initialize(resemblance)
    @resemblance = resemblance
  end

  def view_template
    div style: { border: "1px solid", padding: "10px", margin: "10px" } do
      render @resemblance
      render Components::Identity.new(@resemblance.past_identity)
      render Components::Inspector.new(@resemblance)
    end
  end
end
