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

  throttle("login_verify/ip", limit: 20, period: 5.minutes) do |req|
    if req.path.match?(%r{^/login/.+/(verify|totp|backup_code)$}) && req.post?
      req.ip
    end
  end

  # Deliberately loose for an IP bucket: switching is bounded by what is already
  # signed into the browser (BrowserSession::MAX_ACCOUNTS), and our users share
  # school NATs, so a tight per-IP limit punishes a whole building for one busy
  # tab. The browser session cookie can't be the key — it rotates on every switch.
  throttle("account_switch/ip", limit: 60, period: 5.minutes) do |req|
    if req.post? && req.path.start_with?("/accounts/")
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

  self.throttled_responder = lambda do |env|
    headers = {
      "Content-Type" => "text/html",
      "Retry-After" => "300" #
    }

    message = "slow your roll!"

    [ 429, headers, [ message ] ]
  end
end
