# Be sure to restart your server when you modify this file.
#
# Uncomment each configuration one by one to switch to the new default.
# Once the app runs with all new defaults, remove this file and set
# `config.load_defaults` to `8.1`.
#
# https://guides.rubyonrails.org/upgrading_ruby_on_rails.html

# JSON renderer no longer escapes <, >, &, U+2028, or U+2029.
# Rails.configuration.action_controller.escape_json_responses = false

# LINE/PARAGRAPH SEPARATOR no longer escaped in JSON (valid in modern JS).
# Rails.configuration.active_support.escape_js_separators_in_json = false

# Raise when order-dependent finders (`#first`, `#second`, ...) have no order
# and the model has no implicit order column / query constraints / primary key.
# Rails.configuration.active_record.raise_on_missing_required_finder_order_columns = true

# Raise UnsafeRedirectError for path-relative redirects without a leading slash
# (`redirect_to "example.com"`, `redirect_to "@attacker.com"`).
# Rails.configuration.action_controller.action_on_path_relative_redirect = :raise

# Track Action View template dependencies with a Ruby parser.
# Rails.configuration.action_view.render_tracker = :ruby

# Omit autocomplete="off" on authenticity-token / method hidden fields.
# Rails.configuration.action_view.remove_hidden_field_autocomplete = true
