require "rails_helper"

RSpec.describe DomainRedirect do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] } }

  def call_on(path, host:, remote_addr: "203.0.113.10")
    env = Rack::MockRequest.env_for("http://#{host}#{path}")
    env["REMOTE_ADDR"] = remote_addr
    middleware.call(env)
  end

  it "does not redirect loopback so container healthchecks can probe any path" do
    status, _headers, body = call_on("/up", host: "localhost", remote_addr: "127.0.0.1")

    expect(status).to eq(200)
    expect(body).to eq([ "ok" ])
  end

  it "does not redirect other loopback paths" do
    status, = call_on("/", host: "identity.hackclub.com", remote_addr: "127.0.0.1")

    expect(status).to eq(200)
  end

  it "still redirects public traffic off identity.hackclub.com" do
    status, headers = call_on("/", host: "identity.hackclub.com")

    expect(status).to eq(301)
    expect(headers["Location"]).to eq("https://auth.hackclub.com/")
  end

  it "does not redirect auth.hackclub.com" do
    status, = call_on("/", host: "auth.hackclub.com")

    expect(status).to eq(200)
  end
end
