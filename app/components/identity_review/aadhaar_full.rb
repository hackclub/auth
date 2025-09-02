class Components::IdentityReview::AadhaarFull < Components::Base
  def initialize(aadhaar_record)
    @aadhaar_record = aadhaar_record
    @data = @aadhaar_record.doc_json[:data]
  end

  def field(key, name)
    res = @data.dig(key)
    return if res.blank?
    li do
      b { "#{name}: " }
      plain res
    end
  end

  def view_template
    h2 { "Full Aadhaar data:" }
    br

    ul style: { list_style_type: "disc" } do
      li do
        b { "Photo:" }
        br
        img src: "data:image/jpeg;base64,#{@data[:photo]}", style: { width: "100px", margin_left: "1em" }
      end
      field :name, "Full name"
      field :"Father Name", "Father's name"
      field :dob, "Date of birth"
      field :aadhar_number, "Aadhaar number"
      field :gender, "Assigned gender"
      field :co, "C/O"
      li do
        b { "Address:" }
        ul style: { margin_left: "1rem", list_style_type: "square" } do
          @data.dig(:address).each do |key, value|
            next if value.blank?
            li { b { "#{key}: " }; plain value }
          end
        end
      end
    end
  end
end
