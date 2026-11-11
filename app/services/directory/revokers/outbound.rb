# frozen_string_literal: true

require "net/http"

module Directory
  module Revokers
    # The one way a revoker talks to the outside world.
    #
    # - resolves the host once, with bounded DNS, and refuses it if any address is internal
    # - connects only to the addresses it checked (Net::HTTP's ipaddr keeps the hostname for
    #   SNI and Host), trying the next one when a connect fails
    # - never through a proxy: a proxy would resolve the host itself and undo the pinning
    # - never follows redirects (Net::HTTP doesn't), always verifies TLS
    # - reads at most BODY_CAP bytes of body, then drops the connection
    # - stays inside DEADLINE overall. no Timeout.timeout: every socket wait is capped at the
    #   time left, so a server dripping one byte at a time still runs out of road
    #
    # network trouble comes back as RevocationFailed, which the job retries. a host that
    # resolves somewhere internal is a config problem and raises ArgumentError.
    module Outbound
      BODY_CAP = 4096
      DEADLINE = 20
      MAX_ADDRESSES = 3
      OPEN_TIMEOUT = 5
      IO_TIMEOUT = 10

      class DeadlineExceeded < StandardError; end
      # could be a typo, could be a DNS outage: retried like any other network failure
      class Unresolvable < StandardError; end
      class StopReading < StandardError; end

      Response = Data.define(:status, :excerpt) do
        def success? = status.between?(200, 299)
      end

      # a dead address just means try the next checked one
      CONNECT_ERRORS = [
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ENETUNREACH, Errno::EHOSTUNREACH,
        Errno::EADDRNOTAVAIL, Errno::ETIMEDOUT, Net::OpenTimeout
      ].freeze

      NETWORK_ERRORS = [
        SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Timeout::Error,
        Net::ProtocolError, Net::HTTPBadResponse, DeadlineExceeded, Unresolvable
      ].freeze

      # caps each read at the time left before the deadline (Net::HTTP only knows a per-read
      # timeout, which a slow drip never trips)
      module DeadlineReads
        attr_accessor :deadline

        private

        def rbuf_fill
          remaining = deadline - Outbound.now
          raise DeadlineExceeded, "no answer within #{DEADLINE}s" if remaining <= 0

          self.read_timeout = [ read_timeout, remaining ].min
          super
        end
      end

      # hands the deadline to the buffered socket Net::HTTP builds in #connect
      module DeadlineConnect
        attr_accessor :deadline

        private

        def connect
          super
          @socket.extend(DeadlineReads)
          @socket.deadline = deadline
        end
      end

      module_function

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def post(url, headers:, body:)
        deadline = now + DEADLINE
        uri = URI.parse(url)
        raise ArgumentError, "revoker url must be http(s)" unless uri.is_a?(URI::HTTP) && uri.hostname.present?

        addresses = Directory::AppRevoker.resolve(uri.hostname)
        raise Unresolvable, "#{uri.hostname} didn't resolve" if addresses.empty?
        if addresses.any? { |ip| Directory::AppRevoker.internal_ip?(ip) }
          raise ArgumentError, "#{uri.hostname} resolves to a private or local address"
        end

        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = body

        http = connect(uri, addresses.first(MAX_ADDRESSES), deadline)
        begin
          read(http, request)
        ensure
          http.finish if http.started?
        end
      rescue *NETWORK_ERRORS => e
        raise Directory::RevokeSessionJob::RevocationFailed, "#{e.class}: #{e.message}".truncate(300)
      end

      def connect(uri, addresses, deadline)
        last_error = nil
        addresses.each do |ip|
          remaining = deadline - now
          raise DeadlineExceeded, "couldn't connect within #{DEADLINE}s" if remaining <= 0

          # nil proxy address: Net::HTTP would otherwise pick one up from the environment
          http = Net::HTTP.new(uri.hostname, uri.port, nil)
          http.extend(DeadlineConnect)
          http.deadline = deadline
          http.ipaddr = ip.to_s
          http.use_ssl = uri.scheme == "https"
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.open_timeout = [ OPEN_TIMEOUT, remaining ].min
          http.write_timeout = [ IO_TIMEOUT, remaining ].min
          http.read_timeout = [ IO_TIMEOUT, remaining ].min
          http.max_retries = 0
          begin
            http.start
            return http
          rescue *CONNECT_ERRORS => e
            last_error = e
          rescue Exception # rubocop:disable Lint/RescueException -- close whatever got opened, then let it go
            http.finish if http.started?
            raise
          end
        end
        raise last_error
      end

      # raising out of the response block makes Net::HTTP drop the connection instead of
      # reading the rest of the body once the block returns
      def read(http, request)
        status = nil
        excerpt = +""
        begin
          http.request(request) do |response|
            status = response.code.to_i
            raise StopReading if status.between?(200, 299)

            response.read_body do |chunk|
              excerpt << chunk
              raise StopReading if excerpt.bytesize >= BODY_CAP
            end
          end
        rescue StopReading
          nil
        end
        Response.new(status: status, excerpt: excerpt.byteslice(0, BODY_CAP).scrub.truncate(500))
      end
    end
  end
end
