# frozen_string_literal: true

desc "nuke PII on an identity and associated records, given an identifier (id, public_id, or email). IRREVERSIBLE."
task :deletion_request, [:identifier] => :environment do |_t, args|
  unless ENV["DELETION_REQUEST_CONFIRM"] == "true"
    abort "safety check: set DELETION_REQUEST_CONFIRM=true to proceed. this action is IRREVERSIBLE."
  end

  identifier = args[:identifier]
  abort "usage: rake deletion_request[identifier] (numeric ID, public_id, or email)" if identifier.blank?

  scope = Identity.with_deleted
  identity = if identifier.match?(/\A\d+\z/)
    scope.find_by(id: identifier)
  elsif identifier.start_with?("ident!")
    scope.find_by_public_id(identifier)
  else
    scope.find_by(primary_email: identifier.downcase)
  end

  abort "identity not found for: #{identifier}" unless identity

  if identity.primary_email&.end_with?("@identity.invalid")
    puts "identity #{identity.id} is already tombstoned. nothing to do."
    exit 0
  end

  puts "=== DELETION REQUEST ==="
  puts "identity ##{identity.id} (#{identity.public_id})"
  puts "name: #{identity.full_name}"
  puts "email: #{identity.primary_email}"
  puts "created: #{identity.created_at}"
  puts ""

  DeletionService.execute_deletion(
    identity,
    privacy_request_reference: ENV.fetch("PRIVACY_REF", "rake task — no reference provided"),
    logger: method(:puts)
  )

  puts ""
  puts "=== DONE ==="
  puts "identity #{identity.id} (#{identity.public_id}) has been tombstoned."
rescue DeletionService::Error => e
  abort e.message
end
