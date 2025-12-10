module OnboardingScenarios
  class Base
    class << self
      # Optional slug for /join/:slug routing. Default: no slug
      def slug = nil

      def find_by_slug(slug)
        return nil if slug.blank?
        descendants&.find { |k| k.slug && k.slug.to_s == slug.to_s }
      end

      def available_slugs
        descendants&.filter_map(&:slug)&.sort || []
      end
    end

    def initialize(identity)
      @identity = identity
    end

    def title = "Create your account"

    def form_fields = []

    def extract_params_proc
      permitted = form_fields
      proc {
        params.require(:identity).permit(*permitted)
              .to_h
              .symbolize_keys
      }
    end

    # Used to guide post-signup flow. For now: :home or :slack
    def next_action = :home

    # Whether this scenario accepts adult (>18) users
    def accepts_adults = false

    # Whether this scenario accepts users under 13
    def accepts_under13 = false

    # Slack provisioning settings
    # Returns :full_member or :multi_channel_guest
    def slack_user_type = :multi_channel_guest

    # Returns array of channel names/IDs for multi-channel guests during onboarding
    def slack_channels = []

    # Returns array of channel names/IDs to add when promoting guest to full member
    def promotion_channels = []

    # Returns :internal_tutorial or :external_program
    def slack_onboarding_flow = :external_program

    # Whether this scenario should provision a Slack account
    def should_create_slack? = true

    # Whether Ralsei should message users via DM instead of a channel
    def use_dm_channel? = false

    # Define the dialogue flow as an ordered list of steps
    # Each step maps to a template and optionally defines the next step
    def dialogue_flow
      {
        intro: { template: "tutorial/01_intro", next: :hacker_values },
        hacker_values: { template: "tutorial/02_hacker_values", next: :welcome },
        welcome: { template: "tutorial/03_welcome", next: nil }
      }
    end

    # The first step in the flow
    def first_step = :intro

    # Get step config
    def step_config(step) = dialogue_flow[step.to_sym]

    # Resolve step to template path
    def template_for(step)
      config = dialogue_flow[step.to_sym]
      case config
      when String then config
      when Hash then config[:template] || "tutorial/#{step}"
      else "tutorial/#{step}"
      end
    end

    # Get next step in the flow
    def next_step(current_step)
      config = dialogue_flow[current_step.to_sym]
      config.is_a?(Hash) ? config[:next] : nil
    end

    # Bot persona - override to customize name/avatar
    def bot_name = nil
    def bot_icon_url = nil

    # Custom dialogue flow hooks - override in subclasses
    def before_first_message = nil
    def after_promotion = nil

    # Handle custom actions - return step symbol, template string, or hash
    def handle_action(action_id) = nil

    private

    def chans(*keys) = Rails.configuration.slack_channels.slice(*keys).values

    def identity_promoted? = @identity.promote_click_count >= 1
  end
end
