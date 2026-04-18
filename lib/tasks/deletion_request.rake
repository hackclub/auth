# frozen_string_literal: true

desc "nuke PII on an identity and associated records, given an identifier (id, public_id, or email). IRREVERSIBLE."
task :deletion_request, [:identifier] => :environment do |_t, args|
  unless ENV["DELETION_REQUEST_CONFIRM"] == "true"
    abort "safety check: set DELETION_REQUEST_CONFIRM=true to proceed. this action is IRREVERSIBLE."
  end

  identifier = args[:identifier]
  abort "usage: rake deletion_request[identifier] (numeric ID, public_id, or email)" if identifier.blank?

  identity = resolve_identity(identifier)
  abort "identity not found for: #{identifier}" unless identity

  if identity.primary_email&.end_with?("@identity.invalid")
    puts "identity #{identity.id} is already tombstoned. nothing to do."
    exit 0
  end

  if identity.backend_user.present?
    abort "identity #{identity.id} has a backend_user record — cannot tombstone admin accounts. remove the backend_user first if this is intentional."
  end

  puts "=== DELETION REQUEST ==="
  puts "identity ##{identity.id} (#{identity.public_id})"
  puts "name: #{identity.full_name}"
  puts "email: #{identity.primary_email}"
  puts "created: #{identity.created_at}"
  puts ""

  original_email = identity.primary_email
  version_items = collect_version_items(identity)
  activity_trackables = collect_activity_trackables(identity)

  ActiveRecord::Base.transaction do
    # step 1: lock account
    puts "step 1: locking account..."
    identity.lock! unless identity.locked?
    destroyed = identity.sessions.destroy_all.length
    puts "  destroyed #{destroyed} sessions"

    # step 2: destroy auth data
    puts "step 2: destroying auth data..."
    {
      "login attempts" => identity.login_attempts,
      "login codes" => identity.login_codes,
      "v2 login codes" => identity.v2_login_codes,
      "TOTP secrets" => identity.totps,
      "backup codes" => identity.backup_codes,
      "WebAuthn credentials" => identity.webauthn_credentials,
      "email change requests" => identity.email_change_requests,
      "OAuth access tokens" => identity.all_access_tokens,
    }.each do |label, assoc|
      count = assoc.destroy_all.length
      puts "  destroyed #{count} #{label}"
    end

    # step 3: purge document files
    puts "step 3: purging document files..."
    purged = purge_attachments(identity)
    puts "  purged #{purged} blobs"

    # step 4: scrub PII on associated records
    puts "step 4: scrubbing associated record PII..."
    identity.addresses.find_each do |address|
      address.update_columns(
        first_name: "[REDACTED]",
        last_name: "[REDACTED]",
        line_1: "[REDACTED]",
        line_2: nil,
        city: "[REDACTED]",
        state: "[REDACTED]",
        postal_code: "[REDACTED]",
        phone_number: "[REDACTED]"
      )
    end
    puts "  scrubbed #{identity.addresses.count} #{"address".pluralize(identity.addresses.count)}"

    legacy_aadhaar_records = Identity::AadhaarRecord.with_deleted.where(identity_id: identity.id)
    legacy_aadhaar_records.find_each do |record|
      record.update_columns(
        name: "[REDACTED]",
        date_of_birth: nil,
        raw_json_response: nil
      )
    end
    puts "  scrubbed #{legacy_aadhaar_records.count} authbridge aadhaar #{"record".pluralize(legacy_aadhaar_records.count)}"

    # step 5: destroy resemblances
    puts "step 5: destroying resemblances..."
    own = Identity::Resemblance.where(identity_id: identity.id).destroy_all.length
    reverse = Identity::Resemblance.where(past_identity_id: identity.id).destroy_all.length
    puts "  destroyed #{own + reverse} #{"resemblance".pluralize(own + reverse)} (#{own} owned, #{reverse} reverse)"

    # step 6: clean up program associations
    puts "step 6: cleaning up program associations..."
    orphaning_apps = Program.where(owner_identity_id: identity.id)
    if orphaning_apps.any?
      orphaning_apps.each do |app|
        puts "  \e[31m⚠ ORPHANING OAuth2 app: \"#{app.name}\" (id: #{app.id})\e[0m"
      end
    end
    collab_email_count = ProgramCollaborator.where(invited_email: identity.primary_email)
      .update_all(invited_email: "[REDACTED]")
    collab_count = identity.program_collaborators.destroy_all.length
    app_count = orphaning_apps.update_all(owner_identity_id: nil)
    puts "  destroyed #{collab_count} #{"collaborator".pluralize(collab_count)}, scrubbed #{collab_email_count} invited #{"email".pluralize(collab_email_count)}, nullified #{app_count} owned #{"app".pluralize(app_count)}"

    # step 7: destroy OAuth access grants
    puts "step 7: destroying OAuth access grants..."
    grant_count = Doorkeeper::AccessGrant.where(resource_owner_id: identity.id).delete_all
    puts "  destroyed #{grant_count} access #{"grant".pluralize(grant_count)}"

    # step 8: discard pending jobs
    puts "step 8: discarding pending jobs..."
    job_count = discard_pending_jobs(identity)
    puts "  discarded #{job_count} pending #{"job".pluralize(job_count)}"

    # step 9: delete PaperTrail versions
    puts "step 9: deleting PaperTrail versions..."
    version_count = delete_versions(version_items)
    puts "  deleted #{version_count} #{"version".pluralize(version_count)}"

    # step 10: scrub PublicActivity parameters
    puts "step 10: scrubbing activity parameters..."
    activity_count = scrub_activities(identity, activity_trackables)
    puts "  scrubbed #{activity_count} #{"activity".pluralize(activity_count)}"

    # step 11: remove Flipper actor gates
    puts "step 11: removing Flipper actor gates..."
    flipper_count = ActiveRecord::Base.connection.delete(
      "DELETE FROM flipper_gates WHERE key = 'actors' AND value = #{ActiveRecord::Base.connection.quote("Identity;#{identity.id}")}"
    )
    puts "  removed #{flipper_count} actor #{"gate".pluralize(flipper_count)}"

    # step 12: scrub the identity record
    puts "step 12: scrubbing identity PII..."
    tombstone_email = "tombstoned+#{identity.id}@identity.invalid"
    identity.update_columns(
      first_name: "[REDACTED]",
      last_name: "[REDACTED]",
      legal_first_name: "[REDACTED]",
      legal_last_name: "[REDACTED]",
      primary_email: tombstone_email,
      birthday: Date.new(1970, 1, 1),
      phone_number: nil,
      slack_dm_channel_id: nil,
      aadhaar_number_ciphertext: nil,
      aadhaar_number_bidx: nil,
      locked_at: identity.locked_at || Time.current,
      permabanned: true,
      deleted_at: identity.deleted_at || Time.current,
      primary_address_id: nil,
      use_two_factor_authentication: false,
      onboarding_scenario: nil
    )
    puts "  email: #{tombstone_email}"

    # step 13: tombstone the email
    puts "step 13: tombstoning email..."
    TombstonedEmail.tombstone!(original_email)
    puts "  email digest stored"

    # step 14: log the tombstoning
    PublicActivity::Activity.create!(
      trackable: identity,
      key: "identity.deletion_request",
      parameters: { tombstoned_at: Time.current.iso8601 }
    )
    puts "step 14: logged deletion_request activity"
  end

  puts ""
  puts "=== DONE ==="
  puts "identity #{identity.id} (#{identity.public_id}) has been tombstoned."
  puts "#{"verification".pluralize(identity.verifications.with_deleted.count)} preserved: #{identity.verifications.with_deleted.count}"
  puts "#{"document record".pluralize(identity.documents.with_deleted.count)} preserved (files zeroed): #{identity.documents.with_deleted.count}"
end

def resolve_identity(identifier)
  scope = Identity.with_deleted
  if identifier.match?(/\A\d+\z/)
    scope.find_by(id: identifier)
  elsif identifier.start_with?("ident!")
    scope.find_by_public_id(identifier)
  else
    scope.find_by(primary_email: identifier.downcase)
  end
end

def collect_version_items(identity)
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

def collect_activity_trackables(identity)
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

def purge_attachments(identity)
  count = 0

  identity.documents.with_deleted.each do |doc|
    doc.files.each do |attachment|
      attachment.purge
      count += 1
    end
  end

  identity.vouch_verifications.with_deleted.each do |vv|
    if vv.evidence.attached?
      vv.evidence.purge
      count += 1
    end
  end

  count
end

def delete_versions(version_items)
  return 0 if version_items.empty?

  total = 0
  version_items.each_slice(100) do |batch|
    conditions = batch.map do |type, id|
      sanitized_type = ActiveRecord::Base.connection.quote(type)
      "(item_type = #{sanitized_type} AND item_id = #{id.to_i})"
    end
    total += PaperTrail::Version.where(conditions.join(" OR ")).delete_all
  end
  total
end

def discard_pending_jobs(identity)
  return 0 unless defined?(GoodJob::Job)

  pending = GoodJob::Job.where(finished_at: nil).where(
    "serialized_params::text LIKE ? OR serialized_params::text LIKE ?",
    "%\"identity_id\":#{identity.id}%",
    "%Identity/#{identity.id}\"%"
  )

  count = 0
  pending.find_each do |job|
    job.update_columns(finished_at: Time.current, error: "discarded by deletion_request rake task")
    count += 1
  end
  count
end

SAFE_ACTIVITY_KEYS = %w[
  oauth_token.create
  oauth_token.revoke
  identity_session.create
  identity.deletion_request
  identity.use_backup_code
].freeze

SAFE_ACTIVITY_KEY_PREFIXES = %w[
  verification.
].freeze

def scrub_activities(identity, activity_trackables)
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
