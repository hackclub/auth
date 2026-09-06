class DomainRedirect
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.host == "auth.hackclub.com" ||
       health_check_path?(request.path) ||
       request.path.start_with?("/api") ||
       (request.path.start_with?("/oauth") && !request.path.start_with?("/oauth/authorize"))
      return @app.call(env)
    end

    # Redirect to auth.hackclub.com
    [ 301, { "Location" => "https://auth.hackclub.com#{request.fullpath}", "Content-Type" => "text/html" }, [] ]
  end

  private

  def health_check_path?(path)
    path == "/up" || path.start_with?("/up.")
  end
end
