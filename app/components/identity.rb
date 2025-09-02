class Components::Identity < Components::Base
  attr_reader :identity

  def initialize(identity, show_legal_name: false)
    @identity = identity
    @show_legal_name = show_legal_name
  end

  def field(label, value = nil)
    b { "#{label}: " }
    if block_given?
      yield
    else
      span { value.to_s }
    end
    br
  end

  def view_template
    div do
      render @identity
      br
      if @identity.legal_first_name.present? && @show_legal_name
        field "Legal First Name", @identity.legal_first_name
        field "Legal Last Name", @identity.legal_last_name
      end
      field "Country", @identity.country
      field "Primary Email", @identity.primary_email
      field "Birthday", @identity.birthday
      field "Phone", @identity.phone_number
      field "Verification status", @identity.verification_status.humanize
      if defined?(@identity.ysws_eligible) && !@identity.ysws_eligible.nil?
        field "YSWS eligible", @identity.ysws_eligible
      end

      field "Slack ID" do
        if identity.slack_id.present?
          a(href: "https://hackclub.slack.com/team/#{identity.slack_id}") do
            identity.slack_id
          end
          copy_to_clipboard(identity.slack_id) do
            plain " (copy)"
          end
        else
          plain "not set"
        end
      end
    end
  end
end
