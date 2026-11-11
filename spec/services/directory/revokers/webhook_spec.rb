# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe Directory::Revokers::Webhook do
  let(:server) { TCPServer.new("127.0.0.1", 0) }
  let(:written) { Concurrent::AtomicFixnum.new(0) }

  before do
    # real sockets: webmock's Net::HTTP stands in for exactly the reading we're testing
    WebMock.disable!
    allow(Directory::AppRevoker).to receive(:resolve).and_return([ IPAddr.new("127.0.0.1") ])
    allow(Directory::AppRevoker).to receive(:internal_ip?).and_return(false)
  end

  after do
    WebMock.enable!
    server.close
  end

  def revoker_for(url)
    record = Directory::AppRevoker.new(adapter: "webhook", config: { url: url }.to_json)
    Directory::Revokers.for(record)
  end

  # answers every request with headers, then writes body (or drips) until the client goes away
  def serve(head)
    Thread.new do
      client = server.accept
      client.readpartial(65_536)
      client.write(head)
      yield client
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError
      nil
    ensure
      client&.close
    end
  end

  def huge_body(client)
    chunk = "a" * 65_536
    800.times do
      client.write(chunk)
      written.update { |v| v + chunk.bytesize }
    end
  end

  [ [ 500, "Internal Server Error" ], [ 200, "OK" ] ].each do |code, reason|
    it "stops reading a #{code} response's body at the cap" do
      thread = serve("HTTP/1.1 #{code} #{reason}\r\nContent-Length: #{800 * 65_536}\r\n\r\n") { |c| huge_body(c) }
      url = "http://hooks.example.test:#{server.addr[1]}/revoke"

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        revoker_for(url).call(email: "p@example.test")
      rescue Directory::RevokeSessionJob::RevocationFailed
        nil
      end
      thread.join(5)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
      # 50MB on offer; only socket buffers' worth should ever leave the server
      expect(written.value).to be < 10_000_000
    end
  end

  it "gives up on a server that drips its headers past the deadline" do
    stub_const("Directory::Revokers::Outbound::DEADLINE", 1)
    thread = serve("HTTP/1.1 200 OK\r\n") do |client|
      40.times do
        client.write("X")
        sleep 0.1
      end
    end
    url = "http://hooks.example.test:#{server.addr[1]}/revoke"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { revoker_for(url).call(email: "p@example.test") }.to raise_error(Directory::RevokeSessionJob::RevocationFailed, /ReadTimeout|DeadlineExceeded/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
    thread.kill
  end

  def open_fds = Dir.children("/dev/fd").size

  it "ignores proxy settings in the environment" do
    thread = serve("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n") { nil }
    url = "http://hooks.example.test:#{server.addr[1]}/revoke"
    dead_proxy = "http://127.0.0.1:1"

    with_env = { "http_proxy" => dead_proxy, "https_proxy" => dead_proxy, "HTTP_PROXY" => dead_proxy, "HTTPS_PROXY" => dead_proxy }
    original = with_env.keys.to_h { |k| [ k, ENV[k] ] }
    begin
      with_env.each { |k, v| ENV[k] = v }
      expect(revoker_for(url).call(email: "p@example.test")).to eq(:ok)
    ensure
      original.each { |k, v| ENV[k] = v }
    end
    thread.join(2)
  end

  it "gives up on a TLS handshake that never finishes, without leaking the socket" do
    stub_const("Directory::Revokers::Outbound::OPEN_TIMEOUT", 1)
    stub_const("Directory::Revokers::Outbound::DEADLINE", 2)
    held = Queue.new
    thread = Thread.new do
      client = server.accept
      held << client
      sleep 5
    rescue IOError
      nil
    end
    url = "https://hooks.example.test:#{server.addr[1]}/revoke"
    before = open_fds

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { revoker_for(url).call(email: "p@example.test") }.to raise_error(Directory::RevokeSessionJob::RevocationFailed)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 4

    held.pop.close
    thread.kill
    # the accepted server-side socket is the only new fd, and it's closed above
    expect(open_fds).to be <= before
  end

  it "bounds DNS against a nameserver that never answers" do
    silent = UDPSocket.new
    silent.bind("127.0.0.1", 0)
    allow(Directory::AppRevoker).to receive(:resolve).and_call_original
    allow(Directory::AppRevoker).to receive(:dns_config).and_return(nameserver_port: [ [ "127.0.0.1", silent.addr[1] ] ], search: [], ndots: 1)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { revoker_for("https://slow.example.test/revoke").call(email: "p@example.test") }
      .to raise_error(Directory::RevokeSessionJob::RevocationFailed, /Unresolvable/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 6
  ensure
    silent&.close
  end
end
