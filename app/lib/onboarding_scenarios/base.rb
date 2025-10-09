module OnboardingScenarios
    class Base
        class << self
            # Optional slug for /join/:slug routing. Default: no slug
            def slug = nil

            # Track descendants for lookup by slug
            def inherited(subclass)
                descendants << subclass
                super
            end

            def descendants
                @descendants ||= []
            end

            def find_by_slug(slug)
                return nil if slug.blank?
                descendants.find { |k| k.slug && k.slug.to_s == slug.to_s }
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
    end
end