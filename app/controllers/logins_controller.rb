class LoginsController < ApplicationController
  layout "logged_out"
    include SAMLHelper
    include SafeUrlValidation
    include AhoyAnalytics

    skip_before_action :authenticate_identity!
    before_action :set_return_to, only: [ :new, :create ]
    before_action :set_attempt, except: [ :new, :create ]
    before_action :validate_browser_token, except: [ :new, :create ]
    before_action :ensure_no_user!

    def new
        @prefill_email = params[:email] if params[:email].present?
    end

    def create
        email = params[:email].to_s.strip.downcase
        identity = Identity.find_by(primary_email: email)
        unless identity
            redirect_to signup_path(email: email, return_to: @return_to)
            return
        end

        attempt = LoginAttempt.create!(
            identity: identity,
            authentication_factors: {},
            provenance: "login",
            next_action: "home",
            return_to: @return_to
        )

        # Store fingerprint info in session for later use
        fp_info = fingerprint_info
        Rails.logger.info "Fingerprint info: #{fp_info.inspect}"
        session[:fingerprint_info] = fp_info

        # Set browser token cookie for security
        cookies.signed["browser_token_#{attempt.to_param}"] = {
            value: attempt.browser_token,
            expires: LoginAttempt::EXPIRATION.from_now,
            httponly: true,
            secure: Rails.env.production?,
            same_site: :lax
        }

        if identity.webauthn_enabled?
            redirect_to webauthn_login_attempt_path(id: attempt.to_param), status: :see_other
        else
            send_v2_login_code(identity, attempt)
            track_event("login.code_sent", is_signup: attempt.provenance == "signup", scenario: analytics_scenario_from_return_to(@return_to))
            redirect_to login_attempt_path(id: attempt.to_param), status: :see_other
        end
    rescue => e
        flash[:error] = e.message
        redirect_to login_path(return_to: @return_to)
    end

    def show
        # If email is already satisfied, skip code entry
        if !@attempt.email_available?
            redirect_to_next_factor
        else
            render :email, status: :unprocessable_entity
        end
    end

    def verify
        # Clear any previous flash to avoid stale error messages
        flash.clear

        code = params[:code].to_s.strip.gsub(/[^0-9]/, "")
        login_code = Identity::V2LoginCode.active.find_by(identity: @identity, code: code)

        unless login_code
            track_event("login.code_failed", reason: "invalid", scenario: analytics_scenario_from_return_to(@attempt.return_to))
            flash.now[:error] = "Invalid or expired code, please try again"
            render :email, status: :unprocessable_entity
            return
        end

        # Ensure this login attempt hasn't already created a session
        if @attempt.session.present?
            flash[:error] = "This login has already been completed"
            redirect_to login_attempt_path(id: @attempt.to_param)
            return
        end

        # Atomically consume the code to prevent race conditions
        updated = Identity::V2LoginCode.where(id: login_code.id, used_at: nil).update_all(
            used_at: Time.current,
            ip_address: request.remote_ip.to_s,
            user_agent: request.user_agent
        )

        unless updated == 1
            track_event("login.code_failed", reason: "used", scenario: analytics_scenario_from_return_to(@attempt.return_to))
            flash.now[:error] = "This code has already been used"
            render :email, status: :unprocessable_entity
            return
        end

        track_event("login.code_verified", scenario: analytics_scenario_from_return_to(@attempt.return_to))

        factors = (@attempt.authentication_factors || {}).dup
        factors[:email] = true
        @attempt.update!(authentication_factors: factors)

        # Check if authentication is complete
        handle_post_verification_redirect
    rescue SessionsHelper::AccountLockedError => e
        flash[:error] = e.message
        redirect_to login_path
    end

    def resend
        send_v2_login_code(@attempt.identity, @attempt)
        track_event("login.code_resent", scenario: analytics_scenario_from_return_to(@attempt.return_to))
        flash[:notice] = "A new code has been sent to #{@identity.primary_email}"
        redirect_to login_attempt_path(id: @attempt.to_param), status: :see_other
    end



    def totp
        render status: :unprocessable_entity
    end

    def verify_totp
        flash.clear
        code = params[:code].to_s.strip.gsub(/[^0-9]/, "")

        totp_instance = @identity.totp
        unless totp_instance&.verify(code, drift_behind: 1, drift_ahead: 1)
            track_event("mfa.totp_failed", scenario: analytics_scenario_from_return_to(@attempt.return_to))
            flash.now[:error] = "Invalid TOTP code, please try again"
            render :totp, status: :unprocessable_entity
            return
        end

        track_event("mfa.totp_succeeded", scenario: analytics_scenario_from_return_to(@attempt.return_to))
        factors = (@attempt.authentication_factors || {}).dup
        factors[:totp] = true
        @attempt.update!(authentication_factors: factors)

        handle_post_verification_redirect
    end

    def backup_code
        render status: :unprocessable_entity
    end

    def verify_backup_code
        flash.clear
        code = params[:code].to_s.strip

        backup = @identity.backup_codes.active.find { |bc| bc.authenticate_code(code) }
        unless backup
            flash.now[:error] = "Invalid backup code"
            render :backup_code, status: :unprocessable_entity
            return
        end

        backup.mark_used!
        track_event("mfa.backup_code_used", scenario: analytics_scenario_from_return_to(@attempt.return_to))

        factors = (@attempt.authentication_factors || {}).dup
        factors[:backup_code] = true
        @attempt.update!(authentication_factors: factors)

        handle_post_verification_redirect
    end

    def webauthn
        render status: :unprocessable_entity
    end

    def skip_webauthn
        # User wants to skip passkey and use email code instead
        send_v2_login_code(@identity, @attempt)
        redirect_to login_attempt_path(id: @attempt.to_param), status: :see_other
    end

    def webauthn_options
        credentials = @identity.webauthn_credentials.pluck(:external_id).map { |id| Base64.urlsafe_decode64(id) }

        options = WebAuthn::Credential.options_for_get(
            allow: credentials,
            user_verification: "preferred"
        )

        session[:webauthn_authentication_challenge] = options.challenge

        render json: options
    end

    def verify_webauthn
        flash.clear

        begin
            # Parse the JSON request body manually since Rails doesn't auto-parse for non-API controllers
            request_body = request.body.read
            request.body.rewind
            credential_data = JSON.parse(request_body)

            webauthn_credential = WebAuthn::Credential.from_get(credential_data)

            # wrap in a transaction with pessimistic locking to prevent race conditions on sign_count
            Identity::WebauthnCredential.transaction do
                credential = @identity.webauthn_credentials.lock.find_by(
                    external_id: Base64.urlsafe_encode64(webauthn_credential.id, padding: false)
                )

                unless credential
                    flash.now[:error] = "Passkey not found"
                    render :webauthn, status: :unprocessable_entity
                    return
                end

                webauthn_credential.verify(
                    session[:webauthn_authentication_challenge],
                    public_key: credential.webauthn_public_key,
                    sign_count: credential.sign_count
                )

                # Update sign_count within the locked transaction
                credential.update!(sign_count: webauthn_credential.sign_count)
            end

            session.delete(:webauthn_authentication_challenge)
            factors = (@attempt.authentication_factors || {}).dup
            factors[:webauthn] = true
            @attempt.update!(authentication_factors: factors)

            handle_post_verification_redirect
        rescue WebAuthn::Error => e
            Rails.logger.error "WebAuthn authentication error: #{e.message}"
            flash.now[:error] = "Passkey verification failed. Please try again or use email code."
            render :webauthn, status: :unprocessable_entity
        rescue => e
            Rails.logger.error "Unexpected WebAuthn error: #{e.message}"
            flash.now[:error] = "An unexpected error occurred. Please try again."
            render :webauthn, status: :unprocessable_entity
        end
    end

    private

    def set_attempt
        @attempt = LoginAttempt.incomplete.active.find_by_hashid!(params[:id])

        @identity = @attempt.identity
    rescue ActiveRecord::RecordNotFound
        flash[:error] = "Invalid login attempt, please start again"
        redirect_to login_path
    end

    def already_logged_in
        if identity_signed_in?
            flash[:info] = "you're already logged in, silly!"
            redirect_to root_path
        end
    end

    def validate_browser_token
        return true if Rails.env.test?
        return true unless @attempt.browser_token

        cookie_token = cookies.signed["browser_token_#{@attempt.to_param}"]
        unless cookie_token
            flash[:error] = "This doesn't seem to be the browser who began this login; please ensure cookies are enabled"
            redirect_to login_path
            return false
        end

        unless ActiveSupport::SecurityUtils.secure_compare(@attempt.browser_token, cookie_token)
            flash[:error] = "Browser token mismatch; please ensure cookies are enabled"
            redirect_to login_path
            return false
        end

        true
    end

    def set_return_to
        @return_to = params[:return_to] if params[:return_to].present?
    end

    def fingerprint_info
        browser_info = Browser.new(request.user_agent)

        # Parse browser with version
        browser = "#{browser_info.name} #{browser_info.full_version}"

        # Parse OS with version
        os = "#{browser_info.platform.name} #{browser_info.platform.version}"

        {
            fingerprint: params[:fingerprint],
            device_info: browser,
            os_info: os,
            timezone: params[:timezone],
            ip: request.remote_ip
        }
    end

    def send_v2_login_code(identity, attempt = nil)
        code = Identity::V2LoginCode.create!(identity: identity, ip_address: request.remote_ip, user_agent: request.user_agent)
        IdentityMailer.v2_login_code(code).deliver_later if defined?(IdentityMailer)
    end

    def handle_post_verification_redirect
        # Only create session if authentication requirements are met
        LoginAttempt.transaction do
            @attempt.lock!

            if @attempt.session_id.present?
                flash[:error] = "This login has already been completed"
                return redirect_to login_attempt_path(id: @attempt.to_param)
            end

            @attempt.mark_complete! if @attempt.may_mark_complete?

            unless @attempt.complete?
                # Need more factors - redirect to next available factor
                return redirect_to_next_factor
            end

            session = sign_in(identity: @identity, fingerprint_info: fingerprint_info)
            @attempt.update!(session: session)
        end

        track_event("login.completed", has_mfa: @identity.use_two_factor_authentication?, next_action: @attempt.next_action, scenario: analytics_scenario_from_return_to(@attempt.return_to))

        scenario = scenario_for_identity(@identity)
        if @identity.slack_id.blank? && (scenario.should_create_slack? || @attempt.next_action == "slack")
            provision_slack_on_first_login(scenario)
        end

        if @attempt.next_action == "slack"
            return redirect_to slack_staging_path if Rails.env.staging?
            if Flipper.enabled?(:are_we_enterprise_yet, current_identity)
                render_saml_response_for("slack")
            else
                flash[:success] = "Logged in!"
                redirect_to root_path
            end
        else
        flash[:success] = "Logged in!"
        safe_return_to = @attempt.return_to
        begin
          redirect_to safe_return_to.presence || root_path
        rescue ActionController::Redirecting::UnsafeRedirectError
          redirect_to root_path
        end
        end
    end

    def provision_slack_on_first_login(scenario)
        slack_result = SCIMService.find_or_create_user(
            identity: @identity,
            scenario: scenario
        )

        if slack_result[:success]
            track_event("slack.provisioned", scenario: scenario.class.slug, user_type: slack_result[:user_type].to_s)
            @identity.update(slack_id: slack_result[:slack_id])
            Rails.logger.info "Slack provisioning successful for #{@identity.id}: #{slack_result[:message]}"

            # Assign workspace/channels after SAML login completes (user is now activated)
            should_assign = slack_result[:created] || slack_result[:needs_workspace_assignment]
            if should_assign && scenario.slack_user_type == :multi_channel_guest && scenario.slack_channels.any?
                AssignSlackWorkspaceJob.perform_later(
                    slack_id: slack_result[:slack_id],
                    user_type: scenario.slack_user_type,
                    channel_ids: scenario.slack_channels,
                    identity_id: @identity.id
                )
            end

            if Flipper.enabled?(:are_we_enterprise_yet, current_identity) && scenario.slack_onboarding_flow == :internal_tutorial
                Tutorial::BeginJob.perform_later(@identity)
            end

            slack_result
        else
            track_event("slack.provision_failed", scenario: scenario.class.slug, error_type: slack_result[:error].to_s.truncate(100))
            Rails.logger.error "Slack provisioning failed for #{@identity.id}: #{slack_result[:error]}"
            Sentry.capture_message(
                "Slack provisioning failed on first login",
                level: :error,
                extra: {
                    identity_public_id: @identity.public_id,
                    identity_email: @identity.primary_email,
                    slack_error: slack_result[:error]
                }
            )
            if scenario.should_create_slack? || @attempt.next_action == "slack"
                flash[:warning] = "We couldn't create your Slack account. Please contact support."
            end
            @attempt.update!(next_action: "home")
            slack_result
        end
    end

    def redirect_to_next_factor
        available = @attempt.available_factors

        if available.include?(:webauthn)
            redirect_to webauthn_login_attempt_path(id: @attempt.to_param), status: :see_other
        elsif available.include?(:totp)
            redirect_to totp_login_attempt_path(id: @attempt.to_param), status: :see_other
        elsif available.include?(:backup_code)
            redirect_to backup_code_login_attempt_path(id: @attempt.to_param), status: :see_other
        else
            # No available factors - this shouldn't happen
            flash[:error] = "Unable to complete authentication"
            redirect_to login_path
        end
    end

    def render_saml_response_for(slug)
        sp_config = SAMLService::Entities.sp_by_slug(slug)
        raise "SP not configured" unless sp_config&.dig(:allow_idp_initiated)

        response = build_saml_response(
            identity: @identity,
            sp_config: sp_config,
            in_response_to: nil
        )

        render_saml_response(saml_response: response, sp_config: sp_config)
    end

    def scenario_for_identity(identity)
        identity.onboarding_scenario_instance
    end
end
