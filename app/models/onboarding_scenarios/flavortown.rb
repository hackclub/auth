module OnboardingScenarios
  class Flavortown < Base
    def self.slug = "flavortown"

    def title
      "Set up your Hack Club account!"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end


    def slack_user_type = :multi_channel_guest

    def next_action = :home

    def slack_onboarding_flow = :internal_tutorial

    def slack_channels = chans(:flavortown_bulletin, :flavortown_esplanade, :flavortown_help, :identity_help)

    def promotion_channels = chans(:flavortown_construction, :library, :lounge, :welcome, :happenings, :community, :neighbourhood)
  end
end
