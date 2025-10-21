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
      existing_slack_id = if Rails.application.config.are_we_enterprise_yet
        find_existing_user_by_email(email)
      else
        SlackService.find_by_email(email)
      end

      if existing_slack_id
        Rails.logger.info "Slack user already exists for #{email}: #{existing_slack_id}"
        return {
          success: true,
          slack_id: existing_slack_id,
          created: false,
          message: "Linked existing Slack account"
        }
      end

      unless Rails.application.config.are_we_enterprise_yet
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
      username = generate_unique_username(identity.primary_email)
      user_type = scenario.slack_user_type

      user_payload = build_user_payload(
        identity: identity,
        username: username,
        user_type: user_type
      )

      Rails.logger.info "Creating Slack user with payload: #{user_payload.inspect}"
      response = client.post("Users", user_payload)

      unless response.success?
        error_msg = response.body.dig("Errors", 0, "description") || response.body["detail"] || "Unknown error"
        Rails.logger.error "Failed to create Slack user: #{error_msg}. Full response: #{response.body.inspect}"

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
        if error_msg.include?("already") || error_msg.include?("duplicate") || error_msg.include?("exists")
          # Try to find the existing user by email using SCIM
          existing_user = find_existing_user_by_email(identity.primary_email)
          if existing_user
            Rails.logger.info "Found existing Slack user via SCIM for #{identity.primary_email}: #{existing_user}"
            return {
              success: true,
              slack_id: existing_user,
              created: false,
              message: "Linked existing Slack account (found via SCIM)"
            }
          end
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
        SlackService.assign_to_workspace(user_id: slack_id, user_type:, channel_ids:)
      end

      Rails.logger.info "Successfully created Slack user #{slack_id} for #{identity.primary_email}"

      {
        success: true,
        slack_id:,
        created: true,
        username:,
        message: "Created new Slack account"
      }
    rescue => e
      Rails.logger.error "Error creating Slack user: #{e.message}"
      Honeybadger.notify(e, context: { identity_id: identity.id, email: identity.primary_email })

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

      # Add guest extension for multi-channel guests
      if user_type == :multi_channel_guest
        payload[:schemas] << "urn:ietf:params:scim:schemas:extension:slack:guest:2.0:User"
        payload[:"urn:ietf:params:scim:schemas:extension:slack:guest:2.0:User"] = { type: "multi" }
      end

      payload
    end
  end
end
