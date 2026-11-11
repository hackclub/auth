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
    stub_const("#{described_class}::DEADLINE", 1)
    thread = serve("HTTP/1.1 200 OK\r\n") do |client|
      40.times do
        client.write("X")
        sleep 0.1
      end
    end
    url = "http://hooks.example.test:#{server.addr[1]}/revoke"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { revoker_for(url).call(email: "p@example.test") }.to raise_error(Timeout::Error)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
    thread.kill
  end
end
