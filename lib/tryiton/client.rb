# frozen_string_literal: true

require "json"
require "uri"
require_relative "version"
require_relative "transport"

module Tryiton
  # Raised for API-level errors and runtime (job) failures.
  #
  #   status      - HTTP status code, or nil for a runtime job failure.
  #   error_name  - the API error name, e.g. "OutOfCredits" / "ProcessingError".
  class Error < StandardError
    attr_reader :status, :error_name

    def initialize(message, status: nil, error_name: nil)
      super(message)
      @status = status
      @error_name = error_name
    end
  end

  # Supported `haircut` values for hairstyle try-on.
  HAIRCUTS = %w[
    Afro BobCut BowlCut BoxBraids BuzzCut Chignon CombOver CornrowBraids CurlyBob
    CurlyShag DoubleBun Dreadlocks FauxHawk FishtailBraid LongCurly LongHairTiedUp
    LongHimeCut LongStraight LongTwintails LongWavy LongWavyCurtainBangs ManBun
    MessyTousled PixieCut Pompadour Ponytail ShortCurlyPixie ShortTwintails
    ShoulderLengthHair Spiky TexturedFringe TwinBraids Updo WavyShag
  ].freeze

  # Client for the TryItOn virtual try-on API.
  #
  #   client = Tryiton::Client.new(api_key: ENV["TRYITON_API_KEY"])
  #   job_id = client.try_on_fashion(
  #     model_image: "https://example.com/model.jpg",
  #     garment_image: "https://example.com/tshirt.jpg",
  #     category: "clothing", subcategory: "tops"
  #   )
  #   urls = client.wait_for_result(job_id)
  #
  # See https://docs.tryiton.now
  class Client
    DEFAULT_BASE_URL = "https://tryiton.now/api/v1"
    USER_AGENT = "tryiton-ruby/#{VERSION}"

    # +timeout+ (seconds) applies to connecting and to each read.
    # +transport+ replaces the HTTP layer: any object whose +call(request)+
    # takes a Tryiton::Request and returns something with +status+ and +body+
    # (see Tryiton::NetHTTPTransport). +timeout+ is ignored when it's given.
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: 60, transport: nil)
      raise Error.new("An api_key is required.", error_name: "ConfigError") if api_key.nil? || api_key.empty?

      @api_key = api_key
      @base_url = base_url.sub(%r{/+\z}, "")
      @transport = transport || NetHTTPTransport.new(timeout: timeout)
    end

    # Put a garment or accessory on a person. Returns the job id.
    # Keys: model_image (required), garment_image (required), category,
    # subcategory, num_samples (1-4), output_format ("png"/"jpeg").
    #
    # Deprecated keys: +mode+ is ignored by the API, and +moderation_level+ is
    # validated but has no effect. Both will be removed in 3.0.
    def try_on_fashion(**params)
      request(:post, "/tryon/fashion", params)["jobId"]
    end

    # Restyle a person's hair. Returns the job id.
    # Keys: face_image (required), haircut (required), hair_color,
    # num_samples (1-4), output_format ("png"/"jpeg").
    def try_on_hairstyle(**params)
      request(:post, "/tryon/hairstyle", params)["jobId"]
    end

    # Ink a design onto skin. Returns the job id.
    # Keys: body_image (required), design_image (required), placement, region,
    # num_samples (1-4), output_format ("png"/"jpeg").
    #
    # +region+ is { x:, y:, w:, h: } normalized 0-1 from the top-left, each side
    # >= 0.06; with it, +placement+ only describes size/style.
    def try_on_tattoo(**params)
      request(:post, "/tryon/tattoo", params)["jobId"]
    end

    # Fetch the current status of a job.
    # Returns { "status" => ..., "output" => [...], "error" => ... }.
    def get_status(job_id)
      data = request(:get, "/status/#{escape_segment(job_id)}")
      { "status" => data["status"] || "processing", "output" => data["output"] || [], "error" => data["error"] }
    end

    # Fetch your current credit balance.
    def get_credits
      request(:get, "/credits")["credits"]
    end

    # -- Live (real-time webcam) try-on ---------------------------------------
    # Server side only. The end user's browser streams with the `tryiton-live`
    # npm package, using the response of start_live_session (session-scoped
    # credentials; never your API key).

    # Live try-on availability and pricing for your account.
    # Returns { "enabled", "secondsPerCredit", "maxSeconds", "minCredits",
    # "maxConcurrentSessions" }.
    def get_live_config
      request(:get, "/live/config").reject { |k, _| k == "ok" }
    end

    # Prepare a garment for live try-on. Do it once per product, ahead of time
    # (e.g. at catalog sync): it's cached per image and category, so starting a
    # session or switching garments later is instant. Passing +category+ is
    # recommended; omit it to let it be detected.
    # Returns { "id", "category", "subcategory", "description", "createdAt" }.
    def prepare_live_garment(garment_image:, category: nil, subcategory: nil)
      body = { garment_image: garment_image, category: category, subcategory: subcategory }
      request(:post, "/live/garments", body)["garment"]
    end

    # Start a live session for one end user. Holds the first credit.
    #   garment_id     - a prepared garment to start with.
    #   max_seconds    - cap this session, 10..maxSeconds.
    #   end_user_id    - your id for the end user: one stream per end user, a
    #                    restart ends their previous one.
    #   allowed_origin - lock the media token to your site, e.g. "https://shop.example.com".
    # Returns the whole response body ("session", "clientSecret", "connection",
    # "secondsPerCredit", "maxSeconds", "secondsLeft", "garment"). Send it to the
    # browser as-is; it streams with connectLiveTryOn from `tryiton-live`.
    def start_live_session(garment_id: nil, max_seconds: nil, end_user_id: nil, allowed_origin: nil)
      body = { garment_id: garment_id, max_seconds: max_seconds, end_user_id: end_user_id, allowed_origin: allowed_origin }
      request(:post, "/live/sessions", body)
    end

    # Status and usage of a live session.
    # Returns { "id", "status", "endReason", "seconds", "creditsCharged", ... }.
    def get_live_session(session_id)
      request(:get, "/live/sessions/#{escape_segment(session_id)}")["session"]
    end

    # End a live session from your server (e.g. the user left). Idempotent.
    # Returns the ended session.
    def stop_live_session(session_id)
      request(:post, "/live/sessions/#{escape_segment(session_id)}/stop", {})["session"]
    end

    # Poll a job until it completes, then return the output image URLs.
    # Raises Tryiton::Error if the job fails or the timeout is reached.
    def wait_for_result(job_id, poll_interval: 2.0, timeout: 120.0)
      deadline = monotonic + timeout
      loop do
        status = get_status(job_id)
        return status["output"] if status["status"] == "completed"

        raise job_error(status["error"]) if status["status"] == "failed"

        raise Error.new("Timed out waiting for job #{job_id}.", error_name: "Timeout") if monotonic > deadline

        sleep(poll_interval)
      end
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # A path segment, percent-encoded (spaces as %20; "+" would reach the
    # server as a literal plus).
    def escape_segment(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    def request(method, path, body = nil)
      headers = { "Authorization" => "Bearer #{@api_key}", "User-Agent" => USER_AGENT }
      json = nil
      unless body.nil?
        headers["Content-Type"] = "application/json"
        json = JSON.generate(body.reject { |_, v| v.nil? })
      end
      http_method = method == :post ? "POST" : "GET"
      req = Request.new(http_method: http_method, url: "#{@base_url}#{path}", headers: headers, body: json)

      begin
        res = @transport.call(req)
      rescue Error
        raise
      rescue StandardError => e
        raise Error.new("Network error: #{e.message}", error_name: "NetworkError")
      end

      raw = res.body.to_s
      data =
        begin
          raw.empty? ? {} : JSON.parse(raw)
        rescue JSON::ParserError
          {}
        end

      data = {} unless data.is_a?(Hash)

      code = res.status.to_i
      raise api_error(data, code) unless (200..299).cover?(code)

      data
    end

    # GET /status returns a failed job's reason as a plain string; accept the
    # { "name", "message" } envelope shape too.
    def job_error(err)
      if err.is_a?(Hash)
        Error.new(err["message"] || "Try-on failed.", error_name: err["name"] || "ProcessingError")
      else
        message = err.is_a?(String) && !err.empty? ? err : "Try-on failed."
        Error.new(message, error_name: "ProcessingError")
      end
    end

    # API envelope: { "ok" => false, "error" => { "name", "message" } }. Older shapes put strings at the top level.
    def api_error(data, code)
      err = data["error"].is_a?(Hash) ? data["error"] : {}
      top_name = data["error"].is_a?(String) ? data["error"] : nil
      message = err["message"] || (data["message"].is_a?(String) ? data["message"] : nil) || "HTTP #{code}"
      Error.new(message, status: code, error_name: err["name"] || top_name)
    end
  end
end
