class IdentitiesController < ApplicationController
  layout "logged_out", only: [:new, :create]
    skip_before_action :authenticate_identity!, only: [ :new, :create ]
    before_action :set_identity, except: [ :new, :create ]
    before_action :set_onboarding_scenario, only: [ :new, :create ]
    before_action :set_return_to, only: [ :new, :create ]
    before_action :ensure_migration_token_present, only: [ :new, :create ]
    before_action :ensure_no_user!, only: [ :new, :create ]

    def edit
        @identity = current_identity
    end

    def update
        @identity = current_identity
        if @identity.update(identity_params)
            flash[:success] = "saved changes!"
            redirect_to edit_identity_path
        else
            render :edit
        end
    end

    def new
        @prefill_attributes = scenario_prefill_attributes
        # Allow email to be prefilled from login redirect
        @prefill_attributes[:primary_email] ||= params[:email] if params[:email].present?
        # Prefill country from GeoIP if not provided
        @prefill_attributes[:country] ||= detected_country_alpha2
        @identity = Identity.new(@prefill_attributes)
    end

    def create
        flash.clear
        @prefill_attributes = scenario_prefill_attributes

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
              flash[:info] = "You already have an account, please log in!"
              return redirect_to login_path(email: attrs[:primary_email], return_to: @return_to)
            end
        end

        if attrs[:birthday].present?
          birthday = attrs[:birthday].is_a?(String) ? Date.parse(attrs[:birthday]) : attrs[:birthday]
          if birthday > Date.today
            flash[:error] = "I'm sorry, I may be gullible but I'm not willing to believe you were born in the future."
            @identity = Identity.new(@prefill_attributes.merge(attrs))
            render :new, status: :unprocessable_entity
            return
          end

          age = (Date.today - birthday).days.in_years

          if age > 18 && !@onboarding_scenario.accepts_adults
            @age_restriction = "Hack Club is a community for teenagers. <br/>Unfortunately, you are not eligible to join.".html_safe
            @identity = Identity.new(@prefill_attributes.merge(attrs))
            render :new, status: :unprocessable_entity
            return
          end

          if age < 13 && !@onboarding_scenario.accepts_under13
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

        # Ensure country is present; if missing, use GeoIP detection with US fallback
        attrs[:country] ||= detected_country_alpha2
        attrs[:onboarding_scenario] = @onboarding_scenario.class.slug
        @identity = Identity.new(attrs)

        if @identity.save
            if @onboarding_scenario.is_a?(OnboardingScenarios::LegacyMigration)
                # Migration flow: skip email code, trust signed token and mark email factor complete
                login_attempt = LoginAttempt.create!(
                    identity: @identity,
                    authentication_factors: { legacy_email: true },
                    provenance: "signup_legacy",
                    next_action: @onboarding_scenario.next_action.to_s
                )

                # If no additional factors are required, sign in immediately
                if login_attempt.may_mark_complete?
                    login_attempt.mark_complete!
                    session_rec = sign_in(identity: @identity, fingerprint_info: { ip: request.remote_ip })
                    @identity.update!(legacy_migrated_at: Time.current)
                    login_attempt.update!(session: session_rec)
                    redirect_to @return_to.presence || root_path, status: :see_other
                    return
                end

                # Additional factor required (e.g., TOTP/SMS). Set browser token and send user to next factor.
                cookies.signed["browser_token_#{login_attempt.to_param}"] = {
                    value: login_attempt.browser_token,
                    expires: LoginAttempt::EXPIRATION.from_now
                }

                redirect_to login_attempt_path(id: login_attempt.to_param, return_to: @return_to), status: :see_other
            else
                provenance = "signup"
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
            end
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

    def ensure_migration_token_present
        return unless params[:route_context] == "migrate"

        token = params[:email_token]
        if token.blank?
            redirect_to signup_path(return_to: @return_to)
            return
        end

        begin
            email = Rails.application.message_verifier(:legacy_email).verify(token)
            if Identity.exists?(primary_email: email, legacy_migrated_at: ..Time.current)
                flash[:info] = "that email address has already been migrated"
                redirect_to login_path(email: email, return_to: @return_to)
                return
            end
        rescue StandardError
            redirect_to signup_path(return_to: @return_to)
            return
        end
    end

    def identity_params
        params.require(:identity).permit(:first_name, :last_name)
    end

    public

    def toggle_2fa
        # Enabling 2FA doesn't need step-up auth
        if !current_identity.use_two_factor_authentication?
            # Can only enable 2FA if at least one 2FA method is set up
            if !current_identity.has_two_factor_method?
                flash[:error] = "You must set up a two-factor authentication method before requiring 2FA"
                redirect_to security_path
                return
            end

            current_identity.update!(use_two_factor_authentication: true)

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