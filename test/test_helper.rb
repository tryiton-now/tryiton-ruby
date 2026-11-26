# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "minitest/autorun"
require "tryiton"

# Stands in for the HTTP layer: replies with the given responses in order and
# records every Tryiton::Request it receives.
class FakeTransport
  attr_reader :requests

  # responses - Array of { status:, body: } (body is the raw String).
  # repeat_last - keep serving the last response once the list runs out.
  def initialize(responses, repeat_last: false)
    @responses = responses.dup
    @repeat_last = repeat_last
    @requests = []
  end

  def call(request)
    @requests << request
    response = @repeat_last && @responses.size == 1 ? @responses.first : @responses.shift
    raise "FakeTransport: unexpected request #{request.http_method} #{request.url}" if response.nil?

    Tryiton::Response.new(status: response[:status], body: response[:body])
  end
end

module ContractFixture
  PATH = File.expand_path("fixtures/sdk-cases.json", __dir__)

  def self.data
    @data ||= JSON.parse(File.read(PATH))
  end

  # A fixture response ({ "status", "body" } or { "status", "raw" }) as the
  # raw HTTP reply FakeTransport serves.
  def self.reply(response)
    raw = response.key?("raw") ? response["raw"] : JSON.generate(response["body"])
    { status: response["status"], body: raw }
  end
end
