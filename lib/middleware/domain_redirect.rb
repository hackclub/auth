class DomainRedirect
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    
    if request.path.start_with?('/api') || request.host == 'account.hackclub.com'
      return @app.call(env)
    end
    
    # Redirect to account.hackclub.com
    [301, { 'Location' => "https://account.hackclub.com#{request.fullpath}", 'Content-Type' => 'text/html' }, []]
  end
end
