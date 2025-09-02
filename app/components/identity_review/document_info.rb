class Components::IdentityReview::DocumentInfo < Components::Base
  def initialize(verification)
    @verification = verification
  end

  def view_template
    div class: "lowered padding" do
      h2(style: "margin-top: 0;") { "Document Information" }
      table style: "width: 100%;" do
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Type:" }
          td(style: "padding: 0.25rem 0;") { @verification.document_type }
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Uploaded:" }
          td(style: "padding: 0.25rem 0;") { @verification.identity_document.created_at.strftime("%B %d, %Y at %I:%M %p") }
        end
        if @verification.identity.country == "IN"
          tr do
            td(style: "font-weight: bold; padding: 0.25rem 0;") { "Suggested Aadhaar password:" }
            td(style: "padding: 0.25rem 0;") { copy_to_clipboard(@verification.identity.suggested_aadhaar_password, tooltip_direction: "e") }
          end
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Status:" }
          td(style: "padding: 0.25rem 0;") do
            span class: (@verification.pending? ? "status-pending" : @verification.approved? ? "status-verified" : "status-rejected") do
              @verification.status.humanize
            end
          end
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Files:" }
          td(style: "padding: 0.25rem 0;") { @verification.identity_document.files.count }
        end
      end
    end
  end
end
