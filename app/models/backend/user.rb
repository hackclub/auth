# == Schema Information
#
# Table name: backend_users
#
#  id                       :bigint           not null, primary key
#  active                   :boolean
#  all_fields_access        :boolean
#  can_break_glass          :boolean
#  human_endorser           :boolean
#  icon_url                 :string
#  manual_document_verifier :boolean
#  program_manager          :boolean
#  super_admin              :boolean
#  username                 :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  credential_id            :string
#  slack_id                 :string
#
# Indexes
#
#  index_backend_users_on_slack_id  (slack_id)
#
class Backend::User < ApplicationRecord
  has_paper_trail

  # Organizer positions - programs this backend user organizes
  has_many :organizer_positions, class_name: "Backend::OrganizerPosition", foreign_key: "backend_user_id", dependent: :destroy
  has_many :organized_programs, through: :organizer_positions, source: :program, class_name: "Program"

  def self.authorize_url(redirect_uri)
    params = {
      client_id: ENV["SLACK_CLIENT_ID"],
      redirect_uri: redirect_uri,
      state: SecureRandom.hex(24),
      user_scope: "users.profile:read,users:read,users:read.email"
    }

    URI.parse("https://slack.com/oauth/v2/authorize?#{params.to_query}")
  end

  def self.from_slack_token(code, redirect_uri)
    # Exchange code for token
    response = HTTP.post("https://slack.com/api/oauth.v2.access", form: {
                                                                    client_id: ENV["SLACK_CLIENT_ID"],
                                                                    client_secret: ENV["SLACK_CLIENT_SECRET"],
                                                                    code: code,
                                                                    redirect_uri: redirect_uri
                                                                  })

    data = JSON.parse(response.body.to_s)

    return nil unless data["ok"]

    # Get users info
    user_response = HTTP.auth("Bearer #{data["authed_user"]["access_token"]}")
                        .get("https://slack.com/api/users.info?user=#{data["authed_user"]["id"]}")

    user_data = JSON.parse(user_response.body.to_s)

    return nil unless user_data["ok"]

    slack_id = data.dig("authed_user", "id")

    user = find_by(slack_id:)

    unless user
      Honeybadger.notify("User #{slack_id} tried to sign into the backend without an account")
      return nil
    end

    unless user.active?
      Honeybadger.notify("User #{slack_id} tried to sign into the backend while inactive")
      return nil
    end

    user.username ||= user_data.dig("user", "profile", "display_name_normalized")
    user.username ||= user_data.dig("user", "profile", "real_name_normalized")
    user.username ||= user_data.dig("user", "profile", "username")
    user.icon_url = user_data.dig("user", "profile", "image_192") || user_data.dig("user", "profile", "image_72")
    # Store the OAuth data
    user.save!
    user
  end

  def activate!
    update!(active: true)
  end

  def deactivate!
    update!(active: false)
  end

  def pretty_roles
    return "Super admin" if super_admin?
    roles = []
    roles << "Program manager" if program_manager?
    roles << "Document verifier" if manual_document_verifier?
    roles << "Endorser" if human_endorser?
    roles << "All fields" if all_fields_access?
    roles.join(", ")
  end

  # Handle organized program IDs for forms
  def organized_program_ids
    organized_programs.pluck(:id)
  end

  def organized_program_ids=(program_ids)
    @pending_program_ids = Array(program_ids).reject(&:blank?)

    # If the user is already persisted, update associations immediately
    if persisted?
      update_organized_programs
    end
  end

  # Callback to handle pending program IDs after save
  after_save :update_organized_programs, if: -> { @pending_program_ids }

  private

  def update_organized_programs
    return unless @pending_program_ids

    # Clear existing organizer positions
    organizer_positions.destroy_all

    # Create new organizer positions for selected programs
    @pending_program_ids.each do |program_id|
      organizer_positions.create!(program_id: program_id)
    end

    @pending_program_ids = nil
  end
end
