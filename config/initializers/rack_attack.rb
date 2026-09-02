class Rack::Attack
  throttle("logins/email", limit: 5, period: 5.minutes) do |req|
    if req.path == "/login" && req.post?
      req.params["email"]&.to_s&.downcase&.presence
    end
  end

  throttle("logins/ip", limit: 10, period: 5.minutes) do |req|
    if req.path == "/login" && req.post?
      req.ip
    end
  end

  throttle("email_verify/attempt", limit: 10, period: 5.minutes) do |req|
    if req.post? && (m = req.path.match(%r{^/login/(.+)/verify$}))
      m[1]
    end
  end

  throttle("totp_login/attempt", limit: 5, period: 5.minutes) do |req|
    if req.post? && (m = req.path.match(%r{^/login/(.+)/totp$}))
      m[1]
    end
  end

  throttle("backup_code_login/attempt", limit: 5, period: 5.minutes) do |req|
    if req.post? && (m = req.path.match(%r{^/login/(.+)/backup_code$}))
      m[1]
    end
  end

  throttle("login_email_trigger/attempt", limit: 3, period: 15.minutes) do |req|
    if req.post? && (m = req.path.match(%r{^/login/(.+)/(resend|webauthn/skip)$}))
      m[1]
    end
  end

  throttle("login_verify/ip", limit: 20, period: 5.minutes) do |req|
    if req.path.match?(%r{^/login/.+/(verify|totp|backup_code)$}) && req.post?
      req.ip
    end
  end

  throttle("step_up_generate/ip", limit: 5, period: 15.minutes) do |req|
    if req.post? && req.path.match?(%r{^/step_up/(send_email_code|resend_email)$})
      req.ip
    end
  end

  throttle("step_up_verify/ip", limit: 10, period: 5.minutes) do |req|
    if req.post? && req.path.match?(%r{^/step_up/(verify|webauthn/verify)$})
      req.ip
    end
  end

  throttle("signup/ip", limit: 5, period: 15.minutes) do |req|
    if req.post? && (req.path == "/signup" || req.path == "/migrate" || req.path == "/slack" || req.path.match?(%r{^/join/}))
      req.ip
    end
  end

  throttle("email_change/ip", limit: 3, period: 1.hour) do |req|
    if req.path == "/email_changes" && req.post?
      req.ip
    end
  end

  throttle("email_change_verify/ip", limit: 10, period: 5.minutes) do |req|
    if req.path.match?(%r{^/email_changes/verify/(old|new)$}) && %w[GET POST].include?(req.request_method)
      req.ip
    end
  end

  throttle("oauth_token/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.path == "/oauth/token" && req.post?
  end

  throttle("global/ip", limit: 1000, period: 1.hour) do |req|
    req.ip unless req.path.start_with?("/api/", "/oauth/")
  end

  # Seconds until the throttle window that matched this request rolls over.
  # rack-attack stashes the matched throttle's period and epoch under
  # `rack.attack.match_data`; falling back to 300 only when it's absent.
  RETRY_AFTER_FALLBACK = 300

  def self.retry_after_for(request)
    match_data = request.env["rack.attack.match_data"]
    period = match_data && match_data[:period].to_i
    return RETRY_AFTER_FALLBACK unless period&.positive?

    epoch_time = (match_data[:epoch_time] || Time.now.to_i).to_i
    period - (epoch_time % period)
  end

  # Machines get a parseable error; humans keep getting yelled at.
  self.throttled_responder = lambda do |request_or_env|
    # rack-attack >= 6 hands us a Rack::Attack::Request; older versions, a raw env.
    request = request_or_env.respond_to?(:path) ? request_or_env : ::Rack::Request.new(request_or_env)
    api_client = ::APIErrors.api_path?(request.path) ||
                 request.get_header("HTTP_ACCEPT").to_s.include?("application/json")
    retry_after = ::Rack::Attack.retry_after_for(request)

    if api_client
      body = ::APIErrors.body(:rate_limited, base_url: request.base_url).merge(retry_after: retry_after)
      [ 429, { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s }, [ body.to_json ] ]
    else
      [ 429, { "Content-Type" => "text/html", "Retry-After" => retry_after.to_s }, [ "slow your roll!" ] ]
    end
  end
end
