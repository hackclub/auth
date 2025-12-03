module DocsHelper
  def docs_by_category
    @all_docs.group_by { |doc| doc[:category] || "General" }
  end

  def doc_nav_link(doc)
    link_to doc[:title], doc_path(slug: doc[:slug]),
            class: "docs-nav-link #{'active' if @doc && @doc[:slug] == doc[:slug]}"
  end

  def stub_identity_with_address(identity)
    address = FactoryBot.build_stubbed(:address, identity: identity)
    identity.define_singleton_method(:addresses) { [ address ] }
    identity.define_singleton_method(:primary_address) { address }
    identity
  end

  def render_api_example(template:, identity: nil, identities: nil, scopes: [ "name" ], color_by_scope: false)
    require "factory_bot_rails"

    controller = API::V1::IdentitiesController.new

    if identity
      controller.instance_variable_set(:@identity, identity)
    end

    if identities
      controller.instance_variable_set(:@identities, identities)
    end

    # Skip authentication by setting instance variables directly
    controller.instance_variable_set(:@current_scopes, scopes)
    controller.define_singleton_method(:current_scopes) { scopes }
    controller.define_singleton_method(:identity_authorized_for_scope?) { |identity, scope| true }
    controller.define_singleton_method(:authenticate!) { nil }

    json_result = controller.render_to_string(
      template: template,
      formats: [ :json ]
    )

    pretty_json = JSON.pretty_generate(JSON.parse(json_result))

    if color_by_scope && identity
      colorize_json_by_scope(template, identity, scopes, pretty_json)
    else
      pretty_json
    end
  end

  private

  def colorize_json_by_scope(template, identity, all_scopes, base_json)
    # Map of scope to color
    scope_colors = {
      "email" => "#0ea5e9",       # sky blue
      "name" => "#a855f7",        # purple
      "slack_id" => "#ec4899",    # pink
      "verification_status" => "#84cc16",  # lime
      "basic_info" => "#10b981",  # green
      "legal_name" => "#f59e0b",  # orange
      "address" => "#ef4444"      # red
    }

    # Priority order for scopes (most specific first)
    # Community scopes (email, name, slack_id) are prioritized over HQ-only scopes
    # If a line appears in multiple scopes, use the first one in this list
    scope_priority = [ "email", "name", "slack_id", "verification_status", "legal_name", "address", "basic_info" ]

    # Helper to normalize line for comparison (strip trailing comma)
    normalize_line = ->(line) { line.sub(/,\s*$/, "") }

    # Generate JSON for each individual scope and collect lines
    scope_to_lines = {}

    all_scopes.each do |scope|
      controller = API::V1::IdentitiesController.new
      controller.instance_variable_set(:@identity, identity)
      controller.instance_variable_set(:@current_scopes, [ scope ])
      controller.define_singleton_method(:current_scopes) { [ scope ] }
      controller.define_singleton_method(:identity_authorized_for_scope?) { |identity, scope| true }
      controller.define_singleton_method(:authenticate!) { nil }

      json_result = controller.render_to_string(template: template, formats: [ :json ])
      pretty = JSON.pretty_generate(JSON.parse(json_result))

      scope_to_lines[scope] = pretty.lines.map(&:rstrip)
    end

    # Generate baseline (no scopes) to identify always-present lines
    controller = API::V1::IdentitiesController.new
    controller.instance_variable_set(:@identity, identity)
    controller.instance_variable_set(:@current_scopes, [])
    controller.define_singleton_method(:current_scopes) { [] }
    controller.define_singleton_method(:identity_authorized_for_scope?) { |identity, scope| true }
    controller.define_singleton_method(:authenticate!) { nil }
    baseline_json = controller.render_to_string(template: template, formats: [ :json ])
    baseline_pretty = JSON.pretty_generate(JSON.parse(baseline_json))
    baseline_lines = baseline_pretty.lines.map(&:rstrip)

    # Colorize each line based on text diff
    lines = base_json.lines
    inside_identity = false
    inside_scopes = false
    identity_depth = 0
    scopes_depth = 0

    colored_lines = lines.map do |line|
      stripped = line.rstrip

      # Track if we're inside the identity object
      is_identity_line = stripped.match?(/["']identity["']/)

      if is_identity_line
        inside_identity = true
        identity_depth = 0
      end

      if inside_identity
        identity_depth += stripped.count("{")
        identity_depth -= stripped.count("}")

        if identity_depth <= 0
          inside_identity = false
        end
      end

      # Track if we're inside the scopes array
      if stripped.match?(/["']scopes["']/)
        inside_scopes = true
        scopes_depth = 0
      end

      if inside_scopes
        scopes_depth += stripped.count("[{")
        scopes_depth -= stripped.count("]}")

        if scopes_depth <= 0 && stripped.match?(/[\]}]/)
          inside_scopes = false
        end
      end

      # Colorize scopes array as a legend
      if inside_scopes
        # Find which scope this line mentions
        scope_name = all_scopes.find { |s| stripped.include?("\"#{s}\"") }
        if scope_name && scope_colors[scope_name]
          color = scope_colors[scope_name]
          next "<span style=\"color: #{color};\">#{ERB::Util.html_escape(line)}</span>"
        else
          next ERB::Util.html_escape(line)
        end
      end

      # Only colorize lines inside identity object (but not the "identity": line itself)
      if !inside_identity || is_identity_line
        next ERB::Util.html_escape(line)
      end

      # Skip lines that match the baseline (like "id" field)
      normalized = normalize_line.call(stripped)
      if baseline_lines.any? { |bl| normalize_line.call(bl) == normalized && normalized.include?('"id"') }
        next ERB::Util.html_escape(line)
      end

      # Find which scopes have this line (in priority order, normalize for comparison)
      scopes_with_line = scope_priority.select do |scope|
        scope_to_lines[scope]&.any? { |scope_line| normalize_line.call(scope_line) == normalized }
      end

      if scopes_with_line.any?
        primary_scope = scopes_with_line.first
        color = scope_colors[primary_scope]
        tooltip = scopes_with_line.join(", ")
        "<span class=\"tooltipped tooltipped--e\" aria-label=\"#{ERB::Util.html_escape(tooltip)}\" style=\"color: #{color};\">#{ERB::Util.html_escape(line)}</span>"
      else
        ERB::Util.html_escape(line)
      end
    end

    colored_lines.join
  end
end
