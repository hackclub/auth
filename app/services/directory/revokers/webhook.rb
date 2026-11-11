# frozen_string_literal: true

require "net/http"

module Directory
  module Revokers
    class Webhook < Base
      BODY_CAP = 4096
      # whole call, headers and all: per-read timeouts alone let a slow drip hold a worker
      DEADLINE = 20

      # raised out of Net::HTTP's response block so it drops the connection instead of
      # reading the rest of the body after the block returns
      class StopReading < StandardError; end

      # the addresses are all checked already, so a dead one just means try the next
      CONNECT_ERRORS = [ Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::EHOSTUNREACH, Errno::EADDRNOTAVAIL, Net::OpenTimeout ].freeze

      # resolve once, check every address, then connect to the one we checked (Net::HTTP's
      # ipaddr keeps the hostname for SNI and the Host header). resolving again inside an
      # http client is what lets a rebinding DNS answer slip a private address past the
      # check. no redirects: Net::HTTP doesn't follow them.
      def call(email:)
        uri = URI.parse(@config["url"])
        addresses = Directory::AppRevoker.resolve(uri.hostname)
        if addresses.empty? || addresses.any? { |ip| Directory::AppRevoker.internal_ip?(ip) }
          raise ArgumentError, "webhook url resolves to a private or local address"
        end

        request = Net::HTTP::Post.new(uri.request_uri, webhook_headers)
        request.body = { email: email }.to_json

        status = nil
        excerpt = +""
        Timeout.timeout(DEADLINE) do
          http = connect(uri, addresses)
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
          ensure
            http.finish if http.started?
          end
        end

        unless status.between?(200, 299)
          raise Directory::RevokeSessionJob::RevocationFailed, "webhook revocation failed: #{status} #{excerpt.byteslice(0, BODY_CAP).scrub.truncate(500)}"
        end

        :ok
      rescue SocketError, SystemCallError, IOError, Net::HTTPBadResponse => e
        raise Directory::RevokeSessionJob::RevocationFailed, "webhook revocation failed: #{e.class}: #{e.message}"
      end

      private

      def connect(uri, addresses)
        last_error = nil
        addresses.each do |ip|
          # hostname, not host: an IPv6 literal without brackets, so SNI and the cert check work
          http = Net::HTTP.new(uri.hostname, uri.port)
          http.ipaddr = ip.to_s
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 5
          http.write_timeout = 5
          http.read_timeout = 10
          return http.tap(&:start)
        rescue *CONNECT_ERRORS => e
          last_error = e
        end
        raise last_error
      end

      def webhook_headers
        headers = { "Content-Type" => "application/json" }
        headers["Authorization"] = "Bearer #{@config['secret']}" if @config["secret"].present?
        headers
      end
    end
  end
end
