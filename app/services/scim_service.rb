module SCIMService
  class << self
    SCIM_BASE_URL = "https://api.slack.com/scim/v2"

    def find_or_create_user(identity:, scenario:)
      if Rails.env.staging?
        Rails.logger.info "Skipping Slack provisioning in staging for #{identity.primary_email}"
        return {
          success: true,
          slack_id: "U_STAGING_#{identity.id}",
          created: true,
          message: "Staging mode: Slack integration disabled"
        }
      end

      email = identity.primary_email

      # Check if user exists - use Web API if not enterprise, SCIM API if enterprise
      existing_slack_id = if Flipper.enabled?(:are_we_enterprise_yet, identity)
        find_existing_user_by_email(email)
      else
        SlackService.find_by_email(email)
      end

      if existing_slack_id
        Rails.logger.info "Slack user already exists for #{email}: #{existing_slack_id}"

        workspace_status = SlackService.user_workspace_status(user_id: existing_slack_id)
        needs_workspace_assignment = workspace_status != :in_workspace && workspace_status != :deactivated

        if workspace_status == :deactivated
          Rails.logger.info "Existing Slack user #{existing_slack_id} is deactivated, skipping workspace assignment"
        elsif needs_workspace_assignment
          Rails.logger.info "Existing Slack user #{existing_slack_id} is not in workspace (status: #{workspace_status}), will need assignment"
          Sentry.capture_message(
            "Existing Slack user found but not in workspace",
            level: :info,
            extra: {
              identity_id: identity.id,
              identity_public_id: identity.public_id,
              identity_email: email,
              slack_id: existing_slack_id,
              workspace_status: workspace_status,
              scenario: scenario.class.name,
              scenario_slug: scenario.class.slug,
              slack_user_type: scenario.slack_user_type,
              slack_channels: scenario.slack_channels,
              onboarding_scenario: identity.onboarding_scenario
            }
          )
        end

        return {
          success: true,
          slack_id: existing_slack_id,
          created: false,
          needs_workspace_assignment: needs_workspace_assignment,
          message: "Linked existing Slack account"
        }
      end

      unless Flipper.enabled?(:are_we_enterprise_yet, identity)
        Rails.logger.info "SCIM user creation disabled (not enterprise yet) for #{email}"
        return {
          success: false,
          error: "No existing Slack account found for #{email}",
          created: false
        }
      end

      Rails.logger.info "No existing Slack user found for #{email}, proceeding to create"

      create_user(identity: identity, scenario: scenario)
    end

    def create_user(identity:, scenario:)
      if Flipper.enabled?(:disable_slack_invites, identity)
        Rails.logger.info "Slack invite creation disabled via Flipper for #{identity.primary_email}"
        return {
          success: false,
          error: "Slack signups are temporarily paused...",
          created: false
        }
      end

      username = generate_unique_username(identity.primary_email)
      user_type = scenario.slack_user_type

      user_payload = build_user_payload(
        identity: identity,
        username: username,
        user_type: user_type
      )

      retries = 0
      max_retries = 1
      response = nil

      loop do
        Rails.logger.info "Creating Slack user with payload: #{user_payload.inspect}"
        response = client.post("Users", user_payload)

        if response.success?
          break
        end

        error_msg = if response.body.is_a?(Hash)
                      response.body.dig("Errors", 0, "description") ||
                        response.body["detail"] ||
                        response.body["message"] ||
                        response.body["error"]
        end

        error_msg ||= "Unknown error (Status #{response.status}): #{response.body.inspect}"

        Rails.logger.error "Failed to create Slack user: #{error_msg}"

        # Check for email_taken error with existing_user ID
        if error_msg =~ /email_taken.*existing_user=(U[A-Z0-9]+)/i
          existing_slack_id = $1
          Rails.logger.info "Email taken, extracted existing Slack user ID: #{existing_slack_id}"
          return {
            success: true,
            slack_id: existing_slack_id,
            created: false,
            message: "Linked existing Slack account (from error response)"
          }
        end

        # Check if user already exists but wasn't found by email lookup
        if error_msg.include?("already") || error_msg.include?("duplicate") || error_msg.include?("exists") || error_msg.include?("email_taken") || error_msg.include?("conflict")
          # Try to find the existing user by email using SCIM
          existing_user = find_existing_user_by_email(identity.primary_email)

          # Fallback to Web API lookup if SCIM failed to find the user
          existing_user ||= SlackService.find_by_email(identity.primary_email)

          if existing_user
            Rails.logger.info "Found existing Slack user for #{identity.primary_email}: #{existing_user}"
            return {
              success: true,
              slack_id: existing_user,
              created: false,
              message: "Linked existing Slack account (found via lookup)"
            }
          end
        end

        # Retry once after 1 second if we get invited_user_not_created error
        if error_msg.include?("invited_user_not_created") && retries < max_retries
          Rails.logger.info "Got invited_user_not_created error, retrying after 1 second..."
          sleep(1)
          retries += 1
          next
        end

        return {
          success: false,
          error: error_msg,
          created: false
        }
      end

      slack_id = response.body["id"]

      if user_type == :multi_channel_guest
        channel_ids = scenario.slack_channels if scenario.slack_channels.any?
        sleep(2)
        assigned = SlackService.assign_to_workspace(user_id: slack_id, user_type:, channel_ids:)
        unless assigned
          Sentry.capture_message(
            "Slack workspace assignment failed after SCIM user creation",
            level: :error,
            extra: {
              identity_id: identity.id,
              identity_public_id: identity.public_id,
              identity_email: identity.primary_email,
              slack_id: slack_id,
              user_type: user_type,
              channel_ids: channel_ids,
              scenario: scenario.class.name,
              scenario_slug: scenario.class.slug,
              onboarding_scenario: identity.onboarding_scenario,
              team_id: SlackService.team_id
            }
          )
        end
      end

      Rails.logger.info "Successfully created Slack user #{slack_id} for #{identity.primary_email}"

      {
        success: true,
        slack_id:,
        created: true,
        username:,
        user_type:,
        message: "Created new Slack account"
      }
    rescue => e
      Rails.logger.error "Error creating Slack user: #{e.message}"
      Sentry.capture_exception(e,
        level: :error,
        tags: { component: "slack", critical: true, operation: "scim_create_user" },
        extra: {
          identity_public_id: identity.public_id,
          identity_email: identity.primary_email
        }
      )

      {
        success: false,
        error: e.message,
        created: false
      }
    end

    def scim_token = ENV["SLACK_SCIM_TOKEN"] || raise("SLACK_SCIM_TOKEN not configured")

    def find_existing_user_by_email(email)
      response = client.get("Users") do |req|
        req.params["filter"] = "emails eq \"#{email}\""
      end

      response.body.dig("Resources", 0, "id")
    rescue => e
      Rails.logger.warn "Error finding existing user by email via SCIM: #{e.message}"
      Sentry.capture_exception(e, tags: { component: "slack", operation: "scim_find_user" }, extra: { email: email })
      nil
    end

    private

    def client
      @client ||= Faraday.new(url: SCIM_BASE_URL) do |f|
        f.headers["Authorization"] = "Bearer #{scim_token}"
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.adapter Faraday.default_adapter
      end
    end

    def username_exists?(username)
      response = client.get("Users") do |req|
        req.params["filter"] = "userName eq \"#{username}\""
      end

      response.body["Resources"]&.any? || false
    rescue => e
      Rails.logger.warn "Error checking username existence: #{e.message}"
      Sentry.capture_exception(e, tags: { component: "slack", operation: "scim_check_username" }, extra: { username: username })
      false
    end

    def generate_unique_username(email)
      base_username = email.split("@").first.gsub(/[^a-z0-9_\-.]/, "").downcase[0..20]
      username = base_username
      counter = 1

      while username_exists?(username)
        suffix = counter.to_s
        max_base_length = 21 - suffix.length
        username = "#{base_username[0...max_base_length]}#{suffix}"
        counter += 1
      end

      username
    end

    def build_user_payload(identity:, username:, user_type:)
      payload = {
        schemas: %w[urn:ietf:params:scim:schemas:core:2.0:User urn:ietf:params:scim:schemas:extension:enterprise:2.0:User urn:ietf:params:scim:schemas:extension:slack:profile:2.0:User],
        userName: username,
        name: {
          givenName: identity.first_name,
          familyName: identity.last_name
        },
        emails: [
          {
            value: identity.primary_email,
            primary: true
          }
        ],
        "urn:ietf:params:scim:schemas:extension:slack:profile:2.0:User": {
          startDate: Time.current.iso8601
        }
      }

      # Set timezone based on user's browser
      tz = timezone_for_identity(identity)
      if tz.present?
        payload[:timezone] = tz
        Rails.logger.info "Setting Slack timezone to #{tz} for #{identity.primary_email}"
      end

      # Add guest extension for multi-channel guests
      if user_type == :multi_channel_guest
        payload[:schemas] << "urn:ietf:params:scim:schemas:extension:slack:guest:2.0:User"
        payload[:"urn:ietf:params:scim:schemas:extension:slack:guest:2.0:User"] = { type: "multi" }
      end

      payload
    end


    def timezone_for_identity(identity)
      # Prefer browser-detected timezone from the user's most recent session
      session_tz = identity.sessions.order(created_at: :desc).pick(:timezone)
      if session_tz.present?
        begin
          TZInfo::Timezone.get(session_tz)
          return session_tz
        rescue TZInfo::InvalidTimezoneIdentifier
          Rails.logger.warn "Invalid session timezone '#{session_tz}' for identity #{identity.id}"
        end
      end

           # Fall back to country-based timezone
           country_code = identity.country
           if country_code.present?
             begin
               country = TZInfo::Country.get(country_code.to_s)
               zone_id = country.zone_identifiers.first
               return zone_id if zone_id.present?
             rescue TZInfo::InvalidCountryCode
               Rails.logger.warn "Invalid country code '#{country_code}' for timezone lookup"
             end
           end

      nil
    rescue => e
      Rails.logger.warn "Failed to determine timezone for identity #{identity.id}: #{e.message}"
      nil
    end
  end
end
