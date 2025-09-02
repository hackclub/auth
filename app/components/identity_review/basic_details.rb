class Components::IdentityReview::BasicDetails < Components::Base
  def initialize(identity)
    @identity = identity
  end

  def view_template
    div class: "lowered padding" do
      h2(style: "margin-top: 0;") { "Identity Information" }
      table style: "width: 100%;" do
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Name:" }
          td(style: "padding: 0.25rem 0;") { render(@identity) }
        end
        if @identity.legal_first_name.present?
          tr do
            td(style: "font-weight: bold; padding: 0.25rem 0;") { "Legal Name:" }
            td(style: "padding: 0.25rem 0;") {
              "#{@identity.legal_first_name} #{@identity.legal_last_name}"
            }
          end
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Email:" }
          td(style: "padding: 0.25rem 0;") { @identity.primary_email }
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Birthday:" }
          td(style: "padding: 0.25rem 0;") { @identity.birthday.strftime("%B %d, %Y") }
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Age:" }
          td(style: "padding: 0.25rem 0;") { @identity.age.round(2) }
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Country:" }
          td(style: "padding: 0.25rem 0;") { @identity.country }
        end
      end
    end
  end
end
