# frozen_string_literal: true

require "net/http"
require "uri"

module Tryiton
  # An HTTP request as the client hands it to a transport.
  #
  #   http_method - "GET" or "POST".
  #   url         - the absolute URL, query and path already escaped.
  #   headers     - a Hash of header name => value.
  #   body        - the JSON request body as a String, or nil.
  Request = Struct.new(:http_method, :url, :headers, :body, keyword_init: true)

  # What a transport returns: the HTTP status code (Integer) and the raw
  # response body (String, possibly empty or nil).
  Response = Struct.new(:status, :body, keyword_init: true)

  # The default transport: one Net::HTTP connection per request.
  #
  # Any object with a +call(request)+ method that returns something responding
  # to +status+ and +body+ can stand in for it (pass it as
  # +Client.new(transport: ...)+), e.g. to add retries, logging, a proxy, or a
  # stub in tests. Exceptions it raises reach the caller as a
  # Tryiton::Error named "NetworkError".
  class NetHTTPTransport
    def initialize(timeout: 60)
      @timeout = timeout
    end

    def call(request)
      uri = URI.parse(request.url)
      req = request.http_method == "POST" ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request.headers.each { |name, value| req[name] = value }
      req.body = request.body unless request.body.nil?

      res = Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == "https", open_timeout: @timeout, read_timeout: @timeout
      ) { |http| http.request(req) }

      Response.new(status: res.code.to_i, body: res.body)
    end
  end
end
