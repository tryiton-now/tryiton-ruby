# frozen_string_literal: true

require_relative "test_helper"
require "socket"

# Behavior outside the shared contract: construction, the transport seam,
# network failures, timeouts, and the default Net::HTTP transport on the wire.
class ClientTest < Minitest::Test
  BASE_URL = "https://api.test/api/v1"

  def client(transport, **opts)
    Tryiton::Client.new(api_key: "test-key", base_url: BASE_URL, transport: transport, **opts)
  end

  def ok(body)
    { status: 200, body: JSON.generate(body) }
  end

  def test_version_matches_the_gemspec
    spec = Gem::Specification.load(File.expand_path("../tryiton.gemspec", __dir__))
    assert_equal Tryiton::VERSION, spec.version.to_s
  end

  def test_gemspec_ships_the_signatures
    spec = Gem::Specification.load(File.expand_path("../tryiton.gemspec", __dir__))
    assert_includes spec.files, "sig/tryiton.rbs"
  end

  def test_construction_without_a_transport_still_works
    c = Tryiton::Client.new(api_key: "k")
    assert_instance_of Tryiton::NetHTTPTransport, c.instance_variable_get(:@transport)
    Tryiton::Client.new(api_key: "k", base_url: "https://example.test/api/v1/", timeout: 5)
  end

  def test_missing_api_key_raises_config_error
    [nil, ""].each do |key|
      error = assert_raises(Tryiton::Error) { Tryiton::Client.new(api_key: key) }
      assert_equal "ConfigError", error.error_name
    end
  end

  def test_trailing_slashes_on_base_url_are_dropped
    transport = FakeTransport.new([ok("ok" => true, "credits" => {})])
    Tryiton::Client.new(api_key: "k", base_url: "#{BASE_URL}//", transport: transport).get_credits
    assert_equal "#{BASE_URL}/credits", transport.requests.first.url
  end

  def test_transport_exception_becomes_network_error
    failing = Object.new
    def failing.call(_request)
      raise Errno::ECONNREFUSED
    end
    error = assert_raises(Tryiton::Error) { client(failing).get_credits }
    assert_equal "NetworkError", error.error_name
    assert_nil error.status
    assert_match(/\ANetwork error: /, error.message)
  end

  def test_tryiton_error_from_a_transport_passes_through
    failing = Object.new
    def failing.call(_request)
      raise Tryiton::Error.new("custom", error_name: "Custom")
    end
    error = assert_raises(Tryiton::Error) { client(failing).get_credits }
    assert_equal "Custom", error.error_name
  end

  def test_wait_for_result_times_out
    transport = FakeTransport.new([ok("ok" => true, "status" => "processing", "output" => [])], repeat_last: true)
    error = assert_raises(Tryiton::Error) { client(transport).wait_for_result("j", poll_interval: 0, timeout: 0) }
    assert_equal "Timeout", error.error_name
  end

  def test_wait_for_result_accepts_an_error_envelope_too
    body = { "ok" => true, "status" => "failed", "output" => [], "error" => { "name" => "NoPerson", "message" => "m" } }
    error = assert_raises(Tryiton::Error) { client(FakeTransport.new([ok(body)])).wait_for_result("j", poll_interval: 0) }
    assert_equal ["NoPerson", "m"], [error.error_name, error.message]
  end

  def test_wait_for_result_without_a_reason
    body = { "ok" => true, "status" => "failed", "output" => [], "error" => nil }
    error = assert_raises(Tryiton::Error) { client(FakeTransport.new([ok(body)])).wait_for_result("j", poll_interval: 0) }
    assert_equal ["ProcessingError", "Try-on failed."], [error.error_name, error.message]
  end

  # One real HTTP exchange through NetHTTPTransport against a local socket.
  def test_default_transport_sends_headers_and_body_over_the_wire
    server = TCPServer.new("127.0.0.1", 0)
    captured = {}
    thread = Thread.new do
      sock = server.accept
      captured[:request_line] = sock.gets
      headers = {}
      while (line = sock.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      captured[:headers] = headers
      captured[:body] = sock.read(headers["content-length"].to_i)
      reply = JSON.generate("ok" => true, "jobId" => "job_wire")
      sock.write("HTTP/1.1 201 Created\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
      sock.close
    end

    c = Tryiton::Client.new(api_key: "wire-key", base_url: "http://127.0.0.1:#{server.addr[1]}/api/v1", timeout: 5)
    assert_equal "job_wire", c.try_on_fashion(model_image: "m", garment_image: "g")
    thread.join(5)

    assert_equal "POST /api/v1/tryon/fashion HTTP/1.1\r\n", captured[:request_line]
    assert_equal "tryiton-ruby/#{Tryiton::VERSION}", captured[:headers]["user-agent"]
    assert_equal "Bearer wire-key", captured[:headers]["authorization"]
    assert_equal "application/json", captured[:headers]["content-type"]
    assert_equal({ "model_image" => "m", "garment_image" => "g" }, JSON.parse(captured[:body]))
  ensure
    server&.close
  end
end
