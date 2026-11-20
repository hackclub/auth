class Rack::Attack
  # Normalize once per request: strip trailing slash and file extension so
  # /login/ and /login.json can't bypass throttles. Memoized on the env hash.
  class Request < ::Rack::Request
    def normalized_path
      @normalized_path ||= path.to_s.chomp("/").sub(%r{\.\w+$}, "")
    end
  end

  throttle("logins/email", limit: 5, period: 5.minutes) do |req|
    if req.normalized_path == "/login" && req.post?
      req.params["email"]&.to_s&.downcase&.presence
    end
  end

  throttle("logins/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.normalized_path == "/login" && req.post?
  end

  throttle("email_verify/attempt", limit: 10, period: 5.minutes) do |req|
    if req.post? && (m = req.normalized_path.match(%r{^/login/(.+)/verify$}))
      m[1]
    end
  end

  throttle("totp_login/attempt", limit: 5, period: 5.minutes) do |req|
    if req.post? && (m = req.normalized_path.match(%r{^/login/(.+)/totp$}))
      m[1]
    end
  end

  throttle("backup_code_login/attempt", limit: 5, period: 5.minutes) do |req|
    if req.post? && (m = req.normalized_path.match(%r{^/login/(.+)/backup_code$}))
      m[1]
    end
  end

  throttle("login_email_trigger/attempt", limit: 3, period: 15.minutes) do |req|
    if req.post? && (m = req.normalized_path.match(%r{^/login/(.+)/(resend|webauthn/skip)$}))
      m[1]
    end
  end

  throttle("login_verify/ip", limit: 20, period: 5.minutes) do |req|
    req.ip if req.normalized_path.match?(%r{^/login/.+/(verify|totp|backup_code)$}) && req.post?
  end

  throttle("step_up_generate/ip", limit: 5, period: 15.minutes) do |req|
    req.ip if req.post? && req.normalized_path.match?(%r{^/step_up/(send_email_code|resend_email)$})
  end

  throttle("step_up_verify/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.post? && req.normalized_path.match?(%r{^/step_up/(verify|webauthn/verify)$})
  end

  throttle("signup/ip", limit: 5, period: 15.minutes) do |req|
    req.ip if req.post? && req.normalized_path.in?(%w[/signup /migrate /slack]) || req.normalized_path.match?(%r{^/join/})
  end

  throttle("email_change/ip", limit: 3, period: 1.hour) do |req|
    req.ip if req.normalized_path == "/email_changes" && req.post?
  end

  throttle("email_change_verify/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.normalized_path.match?(%r{^/email_changes/verify/(old|new)$}) && %w[GET POST].include?(req.request_method)
  end

  throttle("oauth_token/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.normalized_path == "/oauth/token" && req.post?
  end

  throttle("global/ip", limit: 1000, period: 1.hour) do |req|
    req.ip unless req.normalized_path.start_with?("/api/", "/oauth/")
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
