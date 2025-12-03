# frozen_string_literal: true

class Components::IdentityReview::AadhaarFull < Components::Base
  def initialize(aadhaar_record)
    @aadhaar_record = aadhaar_record
    @data = @aadhaar_record.doc_json[:data]
  end

  def view_template
    div class: "aadhaar-data" do
      detail_row("photo") do
        img src: "data:image/jpeg;base64,#{@data[:photo]}", class: "aadhaar-photo"
      end
      field :name, "full name"
      field :"Father Name", "father's name"
      field :dob, "date of birth"
      field :aadhar_number, "aadhaar number"
      field :gender, "assigned gender"
      field :co, "c/o"
      render_address if @data[:address].present?
    end
  end

  private

  def field(key, name)
    value = @data.dig(key)
    return if value.blank?

    detail_row(name, value)
  end

  def render_address
    div class: "detail-row" do
      span(class: "detail-label") { "address" }
      span class: "detail-value" do
        div class: "address-fields" do
          @data[:address].each do |key, value|
            next if value.blank?

            div class: "address-line" do
              b { "#{key}: " }
              plain value
            end
          end
        end
      end
    end
  end

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
