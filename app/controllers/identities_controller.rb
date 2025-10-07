class IdentitiesController < ApplicationController
    skip_before_action :authenticate_identity!, only: [ :new, :create ]
    before_action :set_identity, except: [ :new, :create ]
    before_action :set_onboarding_scenario, only: [ :new, :create ]
    before_action :set_return_to, only: [ :new, :create ]

    def new
        @prefill_attributes = scenario_prefill_attributes
        # Allow email to be prefilled from login redirect
        @prefill_attributes[:primary_email] ||= params[:email] if params[:email].present?
        @identity = Identity.new(@prefill_attributes)
    end

    def create
        @prefill_attributes = scenario_prefill_attributes

        # Permit fields defined by the scenario
        attrs = params.require(:identity).permit(*@onboarding_scenario.form_fields).to_h.symbolize_keys

        # If a hidden primary_email was submitted (legacy flows), ensure it matches the
        # securely-derived prefill email; ignore if it doesn't.
        posted_email = params.dig(:identity, :primary_email)
        if posted_email.present? && @prefill_attributes[:primary_email].present? && posted_email != @prefill_attributes[:primary_email]
            Rails.logger.warn("Primary email mismatch between hidden field and verified token; ignoring hidden value")
        end

        # Ensure signed/prefilled attributes (like email) override incoming params
        attrs = @prefill_attributes.merge(attrs)

        attrs[:primary_email]&.downcase!

        if attrs[:primary_email].present?
            existing_identity = Identity.find_by(primary_email: attrs[:primary_email])
            if existing_identity
                flash[:info] = "an account with that email already exists, sending you a login code :-)"
                attempt = LoginAttempt.create!(
                    identity: existing_identity,
                    authentication_factors: {},
                    provenance: "login",
                    next_action: "home"
                )

                # Set browser token cookie for security
                cookies.signed["browser_token_#{attempt.to_param}"] = {
                    value: attempt.browser_token,
                    expires: LoginAttempt::EXPIRATION.from_now
                }

                login_code = Identity::V2LoginCode.create!(identity: existing_identity)
                if defined?(IdentityMailer)
                    IdentityMailer.v2_login_code(login_code).deliver_later
                end

                redirect_to login_attempt_path(id: attempt.to_param, return_to: @return_to), status: :see_other
                return
            end
        end

        @identity = Identity.new(attrs)

        if @identity.save
            provenance = @onboarding_scenario.is_a?(OnboardingScenarios::LegacyMigration) ? "signup_legacy" : "signup"
            login_attempt = LoginAttempt.create!(
                identity: @identity,
                authentication_factors: {},
                provenance: provenance,
                next_action: @onboarding_scenario.next_action.to_s
            )

            # Set browser token cookie for security
            cookies.signed["browser_token_#{login_attempt.to_param}"] = {
                value: login_attempt.browser_token,
                expires: LoginAttempt::EXPIRATION.from_now
            }

            login_code = Identity::V2LoginCode.create!(identity: @identity)
            if defined?(IdentityMailer)
                IdentityMailer.v2_login_code(login_code).deliver_later
            end

            redirect_to login_attempt_path(id: login_attempt.to_param, return_to: @return_to), status: :see_other
        else
            render :new, status: :unprocessable_entity
        end
    end

    private

    def set_identity
        @identity = current_identity
    end

    def set_onboarding_scenario
        @onboarding_scenario = scenario_class_from_route.new(current_identity)
    end

    def scenario_class_from_route
        # /signup -> DefaultJoin
        # /migrate -> LegacyMigration
        # /join/:slug -> scenario by slug if available
        if params[:route_context] == "migrate"
            return OnboardingScenarios::LegacyMigration
        elsif params[:route_context] == "join"
            scenario = OnboardingScenarios::Base.find_by_slug(params[:slug])
            return scenario if scenario
        end
        OnboardingScenarios::DefaultJoin
    end

    def scenario_prefill_attributes
        extractor = @onboarding_scenario.extract_params_proc
        return {} unless extractor.respond_to?(:call)
        data = instance_exec(&extractor)
        data.is_a?(Hash) ? data.symbolize_keys.compact_blank : {}
    rescue => e
        Rails.logger.warn("Scenario prefill failed: #{e.message}")
        {}
    end

    def set_return_to
        @return_to = url_from(params[:return_to]) if params[:return_to].present?
    end

    def url_from(param)
        # Basic sanitization - only allow relative paths or approved hosts
        return nil if param.blank?
        uri = URI.parse(param)
        return param if uri.relative?
        # Add allowed hosts check here if needed
        nil
    rescue URI::InvalidURIError
        nil
    end
end