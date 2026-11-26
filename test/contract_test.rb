# frozen_string_literal: true

require_relative "test_helper"

# Runs the shared SDK contract (test/fixtures/sdk-cases.json, generated from
# tryiton/backend/api-contract/sdk-cases.json) against Tryiton::Client.
class ContractTest < Minitest::Test
  FIXTURE = ContractFixture.data
  USER_AGENT = "tryiton-ruby/#{Tryiton::VERSION}"

  # Canonical camelCase param => Ruby keyword.
  KEYWORDS = {
    "modelImage" => :model_image,
    "garmentImage" => :garment_image,
    "category" => :category,
    "subcategory" => :subcategory,
    "mode" => :mode,
    "numSamples" => :num_samples,
    "outputFormat" => :output_format,
    "moderationLevel" => :moderation_level,
    "faceImage" => :face_image,
    "haircut" => :haircut,
    "hairColor" => :hair_color,
    "bodyImage" => :body_image,
    "designImage" => :design_image,
    "placement" => :placement,
    "region" => :region,
    "garmentId" => :garment_id,
    "maxSeconds" => :max_seconds,
    "endUserId" => :end_user_id,
    "allowedOrigin" => :allowed_origin,
  }.freeze

  # Canonical method => [Ruby method, positional params (in order), extra keywords].
  # wait_for_result polls with no delay: sleep(0) is the smallest interval it accepts.
  METHODS = {
    "tryOnFashion" => [:try_on_fashion, [], {}],
    "tryOnHairstyle" => [:try_on_hairstyle, [], {}],
    "tryOnTattoo" => [:try_on_tattoo, [], {}],
    "getStatus" => [:get_status, ["jobId"], {}],
    "getCredits" => [:get_credits, [], {}],
    "waitForResult" => [:wait_for_result, ["jobId"], { poll_interval: 0 }],
    "getLiveConfig" => [:get_live_config, [], {}],
    "prepareLiveGarment" => [:prepare_live_garment, [], {}],
    "startLiveSession" => [:start_live_session, [], {}],
    "getLiveSession" => [:get_live_session, ["sessionId"], {}],
    "stopLiveSession" => [:stop_live_session, ["sessionId"], {}],
  }.freeze

  def self.slug(text)
    text.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
  end

  def test_fixture_covers_every_mapped_method
    used = FIXTURE["methodCases"].map { |c| c["method"] }.uniq
    assert_empty used - METHODS.keys, "unmapped fixture methods"
    assert_empty METHODS.keys - used, "mapped methods with no fixture case"
  end

  def test_user_agent_matches_the_contract_pattern
    assert_match Regexp.new(FIXTURE["userAgent"]["pattern"]), USER_AGENT
    assert_equal USER_AGENT, Tryiton::Client::USER_AGENT
  end

  FIXTURE["methodCases"].each_with_index do |kase, i|
    define_method("test_method_case_#{format('%02d', i)}_#{slug(kase['name'])}") do
      run_method_case(kase)
    end
  end

  FIXTURE["errorCases"].each_with_index do |kase, i|
    { "get_credits" => [:get_credits, [], "/credits"],
      "get_live_session" => [:get_live_session, ["s1"], "/live/sessions/s1"], }.each do |label, (meth, args, path)|
      define_method("test_error_case_#{i}_#{slug(kase['name'])}_via_#{label}") do
        transport = FakeTransport.new([ContractFixture.reply(kase["response"])])
        error = assert_raises(Tryiton::Error) { client(transport).public_send(meth, *args) }
        assert_error(kase["expectError"], error)
        assert_equal 1, transport.requests.size
        assert_request({ "method" => "GET", "path" => path }, transport.requests.first)
      end
    end
  end

  private

  def client(transport)
    Tryiton::Client.new(api_key: FIXTURE["apiKey"], base_url: FIXTURE["baseUrl"], transport: transport)
  end

  def run_method_case(kase)
    meth, positional, extra = METHODS.fetch(kase["method"])
    params = kase["params"].dup
    args = positional.map { |name| params.delete(name) }
    kwargs = params.each_with_object(extra.dup) { |(k, v), h| h[KEYWORDS.fetch(k)] = v }

    transport = FakeTransport.new(kase["responses"].map { |r| ContractFixture.reply(r) })
    call = -> { client(transport).public_send(meth, *args, **kwargs) }

    if kase.key?("expectError")
      error = assert_raises(Tryiton::Error, &call)
      assert_error(kase["expectError"], error)
    elsif kase["expectResultIsResponseBody"]
      assert_equal kase["responses"].last["body"], call.call
    else
      expected = kase["expectResult"]
      expected.nil? ? assert_nil(call.call) : assert_equal(expected, call.call)
    end

    assert_equal kase["expectRequests"].size, transport.requests.size, "request count"
    kase["expectRequests"].zip(transport.requests).each { |exp, req| assert_request(exp, req) }
  end

  def assert_request(expected, req)
    assert_equal expected["method"], req.http_method
    base = FIXTURE["baseUrl"]
    assert req.url.start_with?(base), "#{req.url} is not under #{base}"
    assert_equal expected["path"], req.url[base.size..-1]
    assert_equal FIXTURE["authHeader"], req.headers["Authorization"]
    assert_equal USER_AGENT, req.headers["User-Agent"]

    if req.http_method == "GET"
      assert_nil req.body, "GET must not send a body"
    end
    return unless expected.key?("body")

    refute_nil req.body, "expected a JSON body"
    assert_equal "application/json", req.headers["Content-Type"]
    sent = JSON.parse(req.body)
    assert_kind_of Hash, sent
    assert_equal expected["body"], sent
  end

  def assert_error(expected, error)
    expected["status"].nil? ? assert_nil(error.status) : assert_equal(expected["status"], error.status)
    expected["errorName"].nil? ? assert_nil(error.error_name) : assert_equal(expected["errorName"], error.error_name)
    if expected.key?("messageAnyOf")
      assert_includes expected["messageAnyOf"], error.message
    else
      assert_equal expected["message"], error.message
    end
  end
end
