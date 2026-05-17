# frozen_string_literal: true

module DeletionService
  class Error < StandardError; end

  def self.check_for_email(email)
    Deletion.find_by(email_hash: Deletion.hash_email(email))
  end

  def self.check_for_name_combos(name, dob)
    hashes = Deletion.name_combo_hashes(name, dob)
    return Deletion.none if hashes.empty?

    Deletion.where("name_combos && ARRAY[?]::text[]", hashes)
  end

  def self.check_ip(ip)
    hash = Deletion.hash_ip(ip)
    Deletion.where("session_ips @> ARRAY[?]::text[]", [hash])
  end

  def self.add_tombstone(identity, privacy_request_reference:)
    original_email = identity.primary_email
    name_hashes = Deletion.name_combo_hashes_for_identity(identity)
    ip_hashes = identity.sessions.where.not(ip: nil).distinct.pluck(:ip).map { |ip| Deletion.hash_ip(ip) }
    email_hash = Deletion.hash_email(original_email)

    deletion = Deletion.find_or_initialize_by(email_hash: email_hash)
    deletion.update!(
      name_combos: name_hashes,
      session_ips: ip_hashes,
      privacy_request_reference: privacy_request_reference
    )
    deletion
  end

  def self.execute_deletion(identity, privacy_request_reference:, logger: nil)
    log = logger || method(:puts)

    raise Error, "identity not found" unless identity
    raise Error, "identity is already tombstoned" if identity.primary_email&.end_with?("@identity.invalid")
    raise Error, "cannot tombstone admin accounts — remove backend_user first" if identity.backend_user.present?

    original_email = identity.primary_email
    name_hashes = Deletion.name_combo_hashes_for_identity(identity)
    ip_hashes = identity.sessions.where.not(ip: nil).distinct.pluck(:ip).map { |ip| Deletion.hash_ip(ip) }
    version_items = collect_version_items(identity)
    activity_trackables = collect_activity_trackables(identity)

    ActiveRecord::Base.transaction do
      log.call "step 1: locking account..."
      identity.lock! unless identity.locked?
      identity.sessions.destroy_all

      log.call "step 2: destroying auth data..."
      [
        identity.login_attempts,
        identity.login_codes,
        identity.v2_login_codes,
        identity.totps,
        identity.backup_codes,
        identity.webauthn_credentials,
        identity.email_change_requests,
        identity.all_access_tokens,
      ].each(&:destroy_all)

      log.call "step 3: purging document files..."
      purge_attachments(identity)

      log.call "step 4: scrubbing associated record PII..."
      identity.addresses.find_each do |address|
        address.update_columns(
          first_name: "[REDACTED]", last_name: "[REDACTED]",
          line_1: "[REDACTED]", line_2: nil,
          city: "[REDACTED]", state: "[REDACTED]",
          postal_code: "[REDACTED]", phone_number: "[REDACTED]"
        )
      end

      Identity::AadhaarRecord.with_deleted.where(identity_id: identity.id).find_each do |record|
        record.update_columns(name: "[REDACTED]", date_of_birth: nil, raw_json_response: nil)
      end

      log.call "step 5: destroying resemblances..."
      Identity::Resemblance.where(identity_id: identity.id).destroy_all
      Identity::Resemblance.where(past_identity_id: identity.id).destroy_all

      log.call "step 6: cleaning up program associations..."
      ProgramCollaborator.where(invited_email: identity.primary_email).update_all(invited_email: "[REDACTED]")
      identity.program_collaborators.destroy_all
      Program.where(owner_identity_id: identity.id).update_all(owner_identity_id: nil)

      log.call "step 7: destroying OAuth access grants..."
      Doorkeeper::AccessGrant.where(resource_owner_id: identity.id).delete_all

      log.call "step 8: discarding pending jobs..."
      discard_pending_jobs(identity)

      log.call "step 9: deleting PaperTrail versions..."
      delete_versions(version_items)

      log.call "step 10: scrubbing activity parameters..."
      scrub_activities(identity, activity_trackables)

      log.call "step 11: removing Flipper actor gates..."
      ActiveRecord::Base.connection.delete(
        "DELETE FROM flipper_gates WHERE key = 'actors' AND value = #{ActiveRecord::Base.connection.quote("Identity;#{identity.id}")}"
      )

      log.call "step 12: scrubbing identity PII..."
      tombstone_email = "tombstoned+#{identity.id}@identity.invalid"
      identity.update_columns(
        first_name: "[REDACTED]", last_name: "[REDACTED]",
        legal_first_name: "[REDACTED]", legal_last_name: "[REDACTED]",
        primary_email: tombstone_email,
        birthday: Date.new(1970, 1, 1),
        phone_number: nil, slack_dm_channel_id: nil,
        aadhaar_number_ciphertext: nil, aadhaar_number_bidx: nil,
        locked_at: identity.locked_at || Time.current,
        permabanned: true,
        deleted_at: identity.deleted_at || Time.current,
        primary_address_id: nil,
        use_two_factor_authentication: false,
        onboarding_scenario: nil
      )

      log.call "step 13: creating tombstone record..."
      email_hash = Deletion.hash_email(original_email)
      deletion = Deletion.find_or_initialize_by(email_hash: email_hash)
      deletion.update!(
        name_combos: name_hashes,
        session_ips: ip_hashes,
        privacy_request_reference: privacy_request_reference
      )

      log.call "step 14: logging deletion activity..."
      PublicActivity::Activity.create!(
        trackable: identity,
        key: "identity.deletion_request",
        parameters: { tombstoned_at: Time.current.iso8601 }
      )
    end

    identity
  end

  private_class_method

  def self.collect_version_items(identity)
    items = [["Identity", identity.id]]

    {
      "Address" => identity.addresses.pluck(:id),
      "IdentitySession" => IdentitySession.where(identity_id: identity.id).pluck(:id),
      "LoginAttempt" => LoginAttempt.where(identity_id: identity.id).pluck(:id),
      "Identity::EmailChangeRequest" => Identity::EmailChangeRequest.where(identity_id: identity.id).pluck(:id),
      "Identity::LoginCode" => Identity::LoginCode.where(identity_id: identity.id).pluck(:id),
      "Identity::V2LoginCode" => Identity::V2LoginCode.where(identity_id: identity.id).pluck(:id),
      "Identity::WebauthnCredential" => Identity::WebauthnCredential.where(identity_id: identity.id).pluck(:id),
      "Identity::BackupCode" => Identity::BackupCode.where(identity_id: identity.id).pluck(:id),
      "Identity::TOTP" => Identity::TOTP.where(identity_id: identity.id).pluck(:id),
      "Identity::AadhaarRecord" => Identity::AadhaarRecord.with_deleted.where(identity_id: identity.id).pluck(:id),
      "OAuthToken" => Doorkeeper::AccessToken.where(resource_owner_id: identity.id).pluck(:id),
      "Verification" => Verification.with_deleted.where(identity_id: identity.id).pluck(:id),
      "BreakGlassRecord" => BreakGlassRecord.where(
        "(break_glassable_type = 'Identity' AND break_glassable_id = ?) OR " \
        "(break_glassable_type = 'Identity::Document' AND break_glassable_id IN (?)) OR " \
        "(break_glassable_type = 'Identity::AadhaarRecord' AND break_glassable_id IN (?)) OR " \
        "(break_glassable_type = 'Verification::VouchVerification' AND break_glassable_id IN (?))",
        identity.id,
        Identity::Document.with_deleted.where(identity_id: identity.id).pluck(:id),
        Identity::AadhaarRecord.with_deleted.where(identity_id: identity.id).pluck(:id),
        Verification::VouchVerification.with_deleted.where(identity_id: identity.id).pluck(:id)
      ).pluck(:id),
    }.each do |type, ids|
      ids.each { |id| items << [type, id] }
    end

    items
  end

  def self.collect_activity_trackables(identity)
    trackables = [["Identity", identity.id]]

    {
      "Address" => identity.addresses.pluck(:id),
      "IdentitySession" => IdentitySession.where(identity_id: identity.id).pluck(:id),
      "Verification" => Verification.with_deleted.where(identity_id: identity.id).pluck(:id),
      "Identity::TOTP" => Identity::TOTP.where(identity_id: identity.id).pluck(:id),
      "Identity::WebauthnCredential" => Identity::WebauthnCredential.where(identity_id: identity.id).pluck(:id),
      "OAuthToken" => Doorkeeper::AccessToken.where(resource_owner_id: identity.id).pluck(:id),
    }.each do |type, ids|
      ids.each { |id| trackables << [type, id] }
    end

    trackables
  end

  def self.purge_attachments(identity)
    identity.documents.with_deleted.each do |doc|
      doc.files.each(&:purge)
    end

    identity.vouch_verifications.with_deleted.each do |vv|
      vv.evidence.purge if vv.evidence.attached?
    end
  end

  def self.delete_versions(version_items)
    return if version_items.empty?

    version_items.each_slice(100) do |batch|
      conditions = batch.map do |type, id|
        sanitized_type = ActiveRecord::Base.connection.quote(type)
        "(item_type = #{sanitized_type} AND item_id = #{id.to_i})"
      end
      PaperTrail::Version.where(conditions.join(" OR ")).delete_all
    end
  end

  def self.discard_pending_jobs(identity)
    return unless defined?(GoodJob::Job)

    GoodJob::Job.where(finished_at: nil).where(
      "serialized_params::text LIKE ? OR serialized_params::text LIKE ?",
      "%\"identity_id\":#{identity.id}%",
      "%Identity/#{identity.id}\"%"
    ).find_each do |job|
      job.update_columns(finished_at: Time.current, error: "discarded by deletion_request")
    end
  end

  SAFE_ACTIVITY_KEYS = %w[
    oauth_token.create
    oauth_token.revoke
    identity_session.create
    identity.deletion_request
    identity.use_backup_code
  ].freeze

  SAFE_ACTIVITY_KEY_PREFIXES = %w[verification.].freeze

  def self.scrub_activities(identity, activity_trackables)
    scope = PublicActivity::Activity.where(
      "(trackable_type = 'Identity' AND trackable_id = ?) OR " \
      "(owner_type = 'Identity' AND owner_id = ?) OR " \
      "(recipient_type = 'Identity' AND recipient_id = ?)",
      identity.id, identity.id, identity.id
    )

    activity_trackables.each_slice(100) do |batch|
      batch.group_by(&:first).each do |type, pairs|
        ids = pairs.map(&:last)
        scope = scope.or(PublicActivity::Activity.where(trackable_type: type, trackable_id: ids))
      end
    end

    safe_conditions = SAFE_ACTIVITY_KEYS.map { |k| ActiveRecord::Base.connection.quote(k) }
    safe_sql = "key IN (#{safe_conditions.join(", ")})"
    SAFE_ACTIVITY_KEY_PREFIXES.each do |prefix|
      safe_sql += " OR key LIKE #{ActiveRecord::Base.connection.quote("#{prefix}%")}"
    end

    scope.where.not(parameters: nil).where.not(safe_sql).update_all(parameters: nil)
  end
end
