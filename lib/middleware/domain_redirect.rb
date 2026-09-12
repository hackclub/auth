require "ipaddr"

class DomainRedirect
  LOOPBACK = [
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("::1")
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) if skip_redirect?(request)

    [ 301, { "Location" => "https://auth.hackclub.com#{request.fullpath}", "Content-Type" => "text/html" }, [] ]
  end

  private

  def skip_redirect?(request)
    request.host == "auth.hackclub.com" ||
      loopback?(request.get_header("REMOTE_ADDR")) ||
      request.path.start_with?("/api") ||
      (request.path.start_with?("/oauth") && !request.path.start_with?("/oauth/authorize"))
  end

  def loopback?(addr)
    return false if addr.blank?

    LOOPBACK.any? { |range| range.include?(addr) }
  rescue IPAddr::Error
    false
  end
end
