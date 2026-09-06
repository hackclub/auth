require "rails_helper"

RSpec.describe DomainRedirect do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] } }

  def call_on(path, host:)
    middleware.call(Rack::MockRequest.env_for("http://#{host}#{path}"))
  end

  it "does not redirect /up so container healthchecks can use Host: localhost" do
    status, _headers, body = call_on("/up", host: "localhost")

    expect(status).to eq(200)
    expect(body).to eq([ "ok" ])
  end

  it "lets /up through on identity.hackclub.com" do
    status, = call_on("/up", host: "identity.hackclub.com")

    expect(status).to eq(200)
  end

  it "still redirects other paths off auth.hackclub.com" do
    status, headers = call_on("/", host: "identity.hackclub.com")

    expect(status).to eq(301)
    expect(headers["Location"]).to eq("https://auth.hackclub.com/")
  end

  it "does not redirect auth.hackclub.com" do
    status, = call_on("/", host: "auth.hackclub.com")

    expect(status).to eq(200)
  end
end
