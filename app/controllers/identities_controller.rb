class IdentitiesController < ApplicationController
  layout "logged_out", only: [ :new, :create ]
    include SafeUrlValidation
    include AhoyAnalytics

    skip_before_action :authenticate_identity!, only: [ :new, :create ]
    before_action :set_identity, except: [ :new, :create ]
    before_action :set_onboarding_scenario, only: [ :new, :create ]
    before_action :set_return_to, only: [ :new, :create ]
    before_action :ensure_no_user!, only: [ :new, :create ]

    helper_method :portal_onboarding_scenario

    def edit
        @identity = current_identity
    end

    def update
        @identity = current_identity
        if @identity.update(identity_params)
            @identity.create_activity :update, owner: current_identity, recipient: current_identity
            flash[:success] = t(".success")
            redirect_to edit_identity_path
        else
            render :edit
        end
    end

    def new
        @prefill_attributes = scenario_prefill_attributes
        # Allow fields to be prefilled from URL params
        @prefill_attributes[:primary_email] ||= params[:email] if params[:email].present?
        @prefill_attributes[:first_name] ||= params[:first_name] if params[:first_name].present?
        @prefill_attributes[:last_name] ||= params[:last_name] if params[:last_name].present?
        @prefill_attributes[:country] ||= params[:country] if params[:country].present?
        @prefill_attributes[:birthday] ||= params[:birthday] if params[:birthday].present?
        # Prefill country from GeoIP if not provided
        @prefill_attributes[:country] ||= detected_country_alpha2
        @identity = Identity.new(@prefill_attributes)
    end

    def create
        flash.clear
        @prefill_attributes = scenario_prefill_attributes

        track_event("signup.started", scenario: analytics_scenario, country: detected_country_alpha2)

        # Permit fields defined by the scenario
        attrs = params.require(:identity).permit(*@onboarding_scenario.form_fields).to_h.symbolize_keys

        posted_email = params.dig(:identity, :primary_email)
        if posted_email.present? && @prefill_attributes[:primary_email].present? && posted_email != @prefill_attributes[:primary_email]
            Rails.logger.warn("Primary email mismatch between hidden field and verified token; ignoring hidden value")
        end

        # Ensure signed/prefilled attributes (like email) override incoming params
        attrs = @prefill_attributes.merge(attrs)

        attrs[:primary_email]&.downcase!

        if attrs[:primary_email].present?
            existing_identity = Identity.find_by(primary_email: attrs[:primary_email])
            if existing_identity.present?
              track_event("signup.existing_account", scenario: analytics_scenario)
              flash[:info] = t(".account_exists")
              return redirect_to login_path(email: attrs[:primary_email], return_to: @return_to)
            end
        end

        slack_user_id = attrs[:primary_email].present? ? SlackService.find_by_email(attrs[:primary_email]) : nil

        if attrs[:birthday].present?
          birthday = attrs[:birthday].is_a?(String) ? Date.parse(attrs[:birthday]) : attrs[:birthday]
          if birthday > Date.today
            flash[:error] = t(".birthday_in_future")
            @identity = Identity.new(@prefill_attributes.merge(attrs))
            render :new, status: :unprocessable_entity
            return
          end

          unless slack_user_id.present?
            age = Identity.calculate_age(birthday)

            if age >= 19 && !@onboarding_scenario.accepts_adults
              track_event("signup.age_rejected", scenario: analytics_scenario, rejection_type: "too_old")
              @age_restriction = "Hack Club is a community for teenagers. <br/>Unfortunately, you are not eligible to join.".html_safe
              @identity = Identity.new(@prefill_attributes.merge(attrs))
              render :new, status: :unprocessable_entity
              return
            end

            if age < 13 && !@onboarding_scenario.accepts_under13
              track_event("signup.age_rejected", scenario: analytics_scenario, rejection_type: "under_13")
              age_diff = (13 - age).round
              diff_text = case age_diff
              when 0 then "once you're 13"
              when 1 then "in a year"
              else "in #{age_diff} years"
              end
              @age_restriction = "Hi there. <br/> Unfortunately, for regulatory reasons outside of our control, we can't accept users under 13. We're sorry, we would if we could.<br/>Please come back #{diff_text}, we'd love to have you as a member of our community!".html_safe
              @identity = Identity.new(@prefill_attributes.merge(attrs))
              render :new, status: :unprocessable_entity
              return
            end
          end
        end

        # Ensure country is present; if missing, use GeoIP detection with US fallback
        attrs[:country] ||= detected_country_alpha2
        attrs[:onboarding_scenario] = @onboarding_scenario.class.slug
        @identity = Identity.new(attrs)

        if @identity.save
            track_event("signup.completed", scenario: analytics_scenario, country: @identity.country)

            # If returning to an OAuth flow, skip Slack provisioning redirect
            next_action = if @return_to.present? && @return_to.start_with?("/oauth/authorize")
                            "home"
            else
                            @onboarding_scenario.next_action.to_s
            end

            login_attempt = LoginAttempt.create!(
                identity: @identity,
                authentication_factors: {},
                provenance: "signup",
                next_action: next_action,
                return_to: @return_to
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

            redirect_to login_attempt_path(id: login_attempt.to_param), status: :see_other
        else
            track_event("signup.validation_failed",
              scenario: analytics_scenario,
              error_fields: @identity.errors.attribute_names.map(&:to_s)
            )
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

        # Check if this is an OAuth flow with a program that has a custom onboarding scenario
        if (scenario = scenario_from_oauth_return_to)
            return scenario
        end

        OnboardingScenarios::DefaultJoin
    end

    def scenario_from_oauth_return_to
        return nil unless params[:return_to].present?
        return nil unless params[:return_to].start_with?("/oauth/authorize")

        uri = URI.parse(params[:return_to])
        query_params = URI.decode_www_form(uri.query || "").to_h
        client_id = query_params["client_id"]
        return nil unless client_id

        program = Program.find_by(uid: client_id)
        return nil unless program&.onboarding_scenario.present?

        OnboardingScenarios::Base.find_by_slug(program.onboarding_scenario)
    rescue URI::InvalidURIError
        nil
    end

    def scenario_prefill_attributes
        return {} unless params[:identity].present?
        extractor = @onboarding_scenario.extract_params_proc
        return {} unless extractor.respond_to?(:call)
        data = instance_exec(&extractor)
        data.is_a?(Hash) ? data.symbolize_keys.compact_blank : {}
    rescue => e
        Rails.logger.warn("Scenario prefill failed: #{e.message}")
        {}
    end

    def set_return_to
        @return_to = params[:return_to] if params[:return_to].present?
    end

    def portal_onboarding_scenario = @onboarding_scenario

    def identity_params
        params.require(:identity).permit(:first_name, :last_name, :phone_number, :developer_mode, :saml_debug)
    end

    public

    def toggle_2fa
        # Enabling 2FA doesn't need step-up auth
        if !current_identity.use_two_factor_authentication?
            # Can only enable 2FA if at least one 2FA method is set up
            if !current_identity.has_two_factor_method?
                flash[:error] = t(".must_setup_method")
                redirect_to security_path
                return
            end

            current_identity.update!(use_two_factor_authentication: true)
            TwoFactorMailer.required_authentication_enabled(current_identity).deliver_later

            @totp = current_identity.totp
            if request.headers["HX-Request"]
                render "identity_totps/index", layout: "htmx"
            else
                redirect_to security_path, notice: "2FA requirement enabled"
            end
            return
        end

        # Disabling 2FA requires step-up auth
        redirect_to new_step_up_path(action_type: "disable_2fa")
    end
end
