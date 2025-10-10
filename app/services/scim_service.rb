module SCIMService
  class << self
    SCIM_BASE_URL = "https://api.slack.com/scim/v2"

    def find_or_create_user(identity:, scenario:)
      email = identity.primary_email
      
      # First check if user already exists by email via Slack Web API
      existing_slack_id = SlackService.find_by_email(email)
      
      if existing_slack_id
        Rails.logger.info "Slack user already exists for #{email}: #{existing_slack_id}"
        return {
          success: true,
          slack_id: existing_slack_id,
          created: false,
          message: "Linked existing Slack account"
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
