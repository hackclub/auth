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
    end
end