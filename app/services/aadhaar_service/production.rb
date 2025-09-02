module AadhaarService
  class AadhaarError < StandardError; end
  class FaradayErrorWithResponse < Faraday::Middleware
    def call(env)
      @app.call(env)
    rescue Faraday::Error => e
      response_body = e.response&.dig(:body) || "No response body"
      raise AadhaarError, "#{e.message}. Response: #{response_body}"
    end
  end

  class Production
    # this is stubbed out because exposing the implementation details of how we communicated with our aadhaar provider
    # opens up a route through which a malicious actor could cost us a lot of money.

    # if you think that's the dumbest thing you've ever heard, i'm absolutely with you.
    # there is a reason we stopped using them, but this fact still remains...
  end
end
