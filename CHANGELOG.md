# Changelog

All notable changes to the `tryiton` gem are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - Unreleased

### Added

- Live (real-time webcam) try-on, server side: `get_live_config`, `prepare_live_garment`, `start_live_session`,
  `get_live_session` and `stop_live_session`. The browser streams with the `tryiton-live` npm package.
- Every request sends `User-Agent: tryiton-ruby/<version>` (also available as `Tryiton::Client::USER_AGENT`).
- RBS signatures for the public API in `sig/tryiton.rbs`, shipped with the gem, including record types for the
  response hashes (`Tryiton::status`, `credits`, `live_config`, `live_garment`, `live_session`, `live_session_start`).
- Optional `transport:` keyword on `Client.new` to replace the HTTP layer (retries, logging, proxies, test stubs).
  `Tryiton::NetHTTPTransport` is the default; `Tryiton::Request` and `Tryiton::Response` are the values it exchanges.
- Contract tests (Minitest) that run the shared TryItOn SDK cases, and GitHub Actions CI on Ruby 2.7 to 3.3 plus
  `rbs validate`.

### Fixed

- API errors now carry the backend's `error.name` and `error.message` from the `{ ok: false, error: { ... } }`
  envelope. Before, `message` was `"HTTP 4xx"` and `error_name` was the whole error Hash. Legacy top-level
  `error`/`message` strings are still read.
- `wait_for_result` now raises with the failed job's own reason. `GET /status` reports it as a plain string, which
  was ignored, so the message was always `"Try-on failed."`. `error_name` stays `"ProcessingError"`.
- Job and session ids are escaped with `%20` for spaces instead of `+`, which the server would read as a literal plus.
- A JSON body that isn't an object (e.g. an array) no longer raises `NoMethodError`.
- The `timeout:` given to `Client.new` now also bounds opening the connection, not only reads.

## [2.0.0] - 2026-07-14

### Changed

- **Breaking:** `try_on_clothes` is now `try_on_fashion` and calls `POST /tryon/fashion`, which covers clothing,
  footwear, eyewear, headwear, jewelry and accessories.

## [1.1.0] - 2026-07-14

### Added

- `region:` on `try_on_tattoo`: pin the design to a box `{ x:, y:, w:, h: }`, normalized 0-1 from the body image's
  top-left. With a region, `placement` only describes size and style.

## [1.0.0] - 2026-06-24

### Added

- `num_samples` (1-4) and `output_format` (`png`/`jpeg`) on clothes, hairstyle and tattoo try-on.

### Removed

- **Breaking:** the `seed`, `segmentation_free` and `garment_photo_type` parameters of clothes try-on.

## [0.1.0] - 2026-06-22

### Added

- Initial release: clothes, hairstyle and tattoo try-on, `get_status`, `wait_for_result`, `get_credits` and
  `Tryiton::Error`.

[2.1.0]: https://github.com/tryiton-now/tryiton-ruby/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/tryiton-now/tryiton-ruby/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/tryiton-now/tryiton-ruby/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/tryiton-now/tryiton-ruby/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/tryiton-now/tryiton-ruby/releases/tag/v0.1.0
