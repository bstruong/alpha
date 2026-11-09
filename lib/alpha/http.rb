# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module Alpha
  # Shared HTTPS-aware Net::HTTP helpers. Always enable TLS and certificate
  # verification for https:// endpoints.
  module Http
    module_function

    def start(uri, open_timeout:, read_timeout:)
      parsed = uri.is_a?(URI) ? uri : URI.parse(uri.to_s)
      Net::HTTP.start(parsed.host, parsed.port, open_timeout: open_timeout, read_timeout: read_timeout) do |http|
        if parsed.scheme == "https"
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
        yield http
      end
    end
  end
end
