# frozen_string_literal: true

class Components::IdentityReview::BasicDetails < Components::Base
  def initialize(identity)
    @identity = identity
  end

  def view_template
    div class: "lowered" do
      detail_row("name") { render(@identity) }
      if @identity.legal_first_name.present?
        detail_row("legal name", "#{@identity.legal_first_name} #{@identity.legal_last_name}")
      end
      detail_row("email", @identity.primary_email)
      detail_row("birthday", @identity.birthday.strftime("%B %d, %Y"))
      detail_row("age", @identity.age.round(2))
      detail_row("country", @identity.country)
    end
  end

  private

  def detail_row(label, value = nil, &block)
    div class: "detail-row" do
      span(class: "detail-label") { label }
      span class: "detail-value" do
        if block_given?
          yield
        else
          plain value.to_s
        end
      end
    end
  end
end
