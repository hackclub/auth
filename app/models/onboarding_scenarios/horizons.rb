module OnboardingScenarios
  class Horizons < Base
    def self.slug = "horizons"

    def title = "Welcome to Horizons!"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_channels = chans(:horizons, :horizons_help, :horizons_bulletin, :identity_help, :help, :welcome_to_hack_club, :slack_guide, :library, :lounge, :welcome, :happenings, :community, :announcements, :news_wire)

    def first_step = :welcome

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/horizons/logo.png"
    def background_path = "images/horizons/background.png"

    def card_attributes = { wide_logo: true }

    def dialogue_flow
      {
        welcome: { template: "tutorial/horizons/03_welcome", next: nil },
        horizons_arcana: { template: "tutorial/horizons/04a_arcana", next: nil },
        horizons_sol: { template: "tutorial/horizons/04b_sol", next: nil },
        horizons_equinox: { template: "tutorial/horizons/04c_equinox", next: nil },
        horizons_crux: { template: "tutorial/horizons/04d_crux", next: nil },
        horizons_polaris: { template: "tutorial/horizons/04e_polaris", next: nil },
        horizons_europa: { template: "tutorial/horizons/04f_europa", next: nil }
      }
    end

    def handle_action(action_id)
      case action_id
      when "horizons_join_arcana"
        SlackService.add_to_channels(user_id: @identity.slack_id, channel_ids: chans(:horizons_arcana))
        :horizons_arcana
      when "horizons_join_sol"
        SlackService.add_to_channels(user_id: @identity.slack_id, channel_ids: chans(:horizons_sol))
        :horizons_sol
      when "horizons_join_equinox"
        SlackService.add_to_channels(user_id: @identity.slack_id, channel_ids: chans(:horizons_equinox))
        :horizons_equinox
      when "horizons_join_crux"
        SlackService.add_to_channels(user_id: @identity.slack_id, channel_ids: chans(:horizons_crux))
        :horizons_crux
      when "horizons_join_polaris"
        SlackService.add_to_channels(user_id: @identity.slack_id, channel_ids: chans(:horizons_polaris))
        :horizons_polaris
      when "horizons_join_europa"
        SlackService.add_to_channels(user_id: @identity.slack_id, channel_ids: chans(:horizons_europa))
        :horizons_europa
      end
    end
  end
end
