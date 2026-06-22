# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

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
  #   job_id = client.try_on_clothes(
  #     model_image: "https://example.com/model.jpg",
  #     garment_image: "https://example.com/tshirt.jpg",
  #     category: "clothing", subcategory: "tops"
  #   )
  #   urls = client.wait_for_result(job_id)
  #
  # See https://docs.tryiton.now
  class Client
    DEFAULT_BASE_URL = "https://tryiton.now/api/v1"

    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: 60)
      raise Error.new("An api_key is required.", error_name: "ConfigError") if api_key.nil? || api_key.empty?

      @api_key = api_key
      @base_url = base_url.sub(%r{/+\z}, "")
      @timeout = timeout
    end

    # Put a garment or accessory on a person. Returns the job id.
    # Keys: model_image (required), garment_image (required), category,
    # subcategory, mode, num_samples, output_format, seed, segmentation_free,
    # garment_photo_type, moderation_level.
    def try_on_clothes(**params)
      request(:post, "/tryon/clothes", params)["jobId"]
    end

    # Restyle a person's hair. Returns the job id.
    # Keys: face_image (required), haircut (required), hair_color.
    def try_on_hairstyle(**params)
      request(:post, "/tryon/hairstyle", params)["jobId"]
    end

    # Ink a design onto skin. Returns the job id.
    # Keys: body_image (required), design_image (required), placement.
    def try_on_tattoo(**params)
      request(:post, "/tryon/tattoo", params)["jobId"]
    end

    # Fetch the current status of a job.
    # Returns { "status" => ..., "output" => [...], "error" => ... }.
    def get_status(job_id)
      data = request(:get, "/status/#{URI.encode_www_form_component(job_id)}")
      { "status" => data["status"] || "processing", "output" => data["output"] || [], "error" => data["error"] }
    end

    # Fetch your current credit balance.
    def get_credits
      request(:get, "/credits")["credits"]
    end

    # Poll a job until it completes, then return the output image URLs.
    # Raises Tryiton::Error if the job fails or the timeout is reached.
    def wait_for_result(job_id, poll_interval: 2.0, timeout: 120.0)
      deadline = monotonic + timeout
      loop do
        status = get_status(job_id)
        return status["output"] if status["status"] == "completed"

        if status["status"] == "failed"
          err = status["error"] || {}
          raise Error.new(err["message"] || "Try-on failed.", error_name: err["name"] || "ProcessingError")
        end

        raise Error.new("Timed out waiting for job #{job_id}.", error_name: "Timeout") if monotonic > deadline

        sleep(poll_interval)
      end
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def request(method, path, body = nil)
      uri = URI.parse("#{@base_url}#{path}")
      req =
        case method
        when :post then Net::HTTP::Post.new(uri)
        else Net::HTTP::Get.new(uri)
        end
      req["Authorization"] = "Bearer #{@api_key}"

      unless body.nil?
        compact = body.reject { |_, v| v.nil? }
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(compact)
      end

      begin
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", read_timeout: @timeout) do |http|
          http.request(req)
        end
      rescue StandardError => e
        raise Error.new("Network error: #{e.message}", error_name: "NetworkError")
      end

      data =
        begin
          res.body && !res.body.empty? ? JSON.parse(res.body) : {}
        rescue JSON::ParserError
          {}
        end

      code = res.code.to_i
      unless (200..299).cover?(code)
        raise Error.new(data["message"] || "HTTP #{code}", status: code, error_name: data["error"])
      end

      data
    end
  end
end
