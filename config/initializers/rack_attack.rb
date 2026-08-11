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

  self.throttled_responder = lambda do |env|
    headers = {
      "Content-Type" => "text/html",
      "Retry-After" => "300" #
    }

    message = "slow your roll!"

    [ 429, headers, [ message ] ]
  end
end
