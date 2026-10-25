# the actor side of manual_verification_call_* is computed, not stored:
# membership follows the open case, so opening a case grants the flow and
# closing it revokes it — nothing per-actor to enable, revoke, or leak.
# (storing one actor per case hit flipper's 100-actor limit, and every
# enabled? check loads the whole stored set.)
Flipper.register(:has_open_verification_case) do |actor|
  actor.respond_to?(:verification_cases) && actor.verification_cases.open_cases.exists?
end

Rails.application.configure do
  config.flipper.memoize = true
  config.flipper.preload = true
end

Flipper::UI.configure do |config|
  if Rails.env.production?
    config.banner_text = "this is production. be careful."
    config.banner_class = "warning"
  end

  config.actor_names_source = ->(actor_ids) do
    grouped = actor_ids.each_with_object(Hash.new { |h, k| h[k] = [] }) do |actor_id, result|
      prefix, hash = actor_id.split("!", 2)
      result[prefix] << hash if hash.present?
    end

    actor_names = {}

    grouped.each do |prefix, hashids|
      prefix_info = Shortcodes.public_id_prefixes[prefix]
      next unless prefix_info

      model = prefix_info[:model].constantize rescue next

      hashids.each do |hashid|
        record = model.find_by_hashid(hashid)
        next unless record
        name = record.try(:full_name) || record.try(:name) || record.try(:primary_email) || record.public_id
        actor_names[record.public_id] = name
      end
    end

    actor_names.compact_blank
  end

  config.descriptions_source = ->(_keys) { Rails.configuration.flipper_features }
end
