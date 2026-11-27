# TryItOn Ruby SDK — AI Virtual Try-On API

Official Ruby client for the [TryItOn](https://tryiton.now) virtual try-on API. Add photoreal AI virtual try-on for clothing, accessories, hairstyles, and tattoos to your Ruby or Rails application with a few lines of code.

- Virtual clothing try-on and accessory try-on (eyewear, footwear, headwear, jewelry)
- Hairstyle and tattoo try-on
- Standard library only (no dependencies), with a built-in job polling helper

Full API reference: [docs.tryiton.now](https://docs.tryiton.now) · Get an API key: [tryiton.now/app/developer](https://tryiton.now/app/developer)

## Installation

```bash
gem install tryiton
```

Or add it to your Gemfile:

```ruby
gem "tryiton"
```

Requires Ruby 2.6 or later.

## Quickstart: run a virtual try-on

Submit a garment and a model photo, then wait for the generated result image.

```ruby
require "tryiton"

client = Tryiton::Client.new(api_key: ENV["TRYITON_API_KEY"])

# Submit a clothing try-on
job_id = client.try_on_fashion(
  model_image: "https://example.com/model.jpg",
  garment_image: "https://example.com/tshirt.jpg",
  category: "clothing",
  subcategory: "tops"
)

# Poll until the job completes and return the output image URL(s)
urls = client.wait_for_result(job_id)
puts urls.first # CDN URL, available for 72 hours
```

Image inputs accept a public URL or a base64 data URL (`data:image/png;base64,...`).

## Core parameters

`try_on_fashion` covers clothing and accessory try-on. The most important parameters:

| Parameter | Type | Required | Description |
| --------- | ---- | -------- | ----------- |
| `model_image` | String | Yes | URL or base64 data URL of the person. |
| `garment_image` | String | Yes | URL or base64 data URL of the garment or accessory. |
| `category` | String | No | Item type: `auto`, `clothing`, `eyewear`, `footwear`, `headwear`, `jewelry`, `accessories`, or `others`. `auto` detects it for you. |
| `subcategory` | String | No | Required for `clothing` (`tops`, `bottoms`, `dresses`), `jewelry`, and `accessories`. |

Additional options (`mode` and `moderation_level` for clothing; `num_samples` 1–4 and `output_format` `png`/`jpeg` for every try-on, including hairstyle and tattoo) are documented in the [API reference](https://docs.tryiton.now).

## Other endpoints

```ruby
# Hairstyle try-on (see Tryiton::HAIRCUTS for all supported values)
client.try_on_hairstyle(face_image: face_url, haircut: "BuzzCut", hair_color: "ash blonde")

# Tattoo try-on — place it with free text...
client.try_on_tattoo(body_image: body_url, design_image: design_url, placement: "on the right forearm, small")
# ...or pin the exact spot with a region box (normalized 0-1, from the image's top-left)
client.try_on_tattoo(body_image: body_url, design_image: design_url, region: { x: 0.32, y: 0.18, w: 0.28, h: 0.34 })

# Poll a job manually, or check your credit balance
status  = client.get_status(job_id)  # { "status" => ..., "output" => [...], "error" => ... }
credits = client.get_credits          # { "on_demand" => ..., "subscription" => ..., "purchased" => ..., "reserved" => ... }
```

## Live try-on (real-time webcam)

Your server prepares garments and starts sessions with the API key. The shopper's browser streams with the
[`tryiton-live`](https://www.npmjs.com/package/tryiton-live) npm package, using only the session-scoped response.

```ruby
# Once per product, e.g. at catalog sync (cached per image + category):
garment = client.prepare_live_garment(garment_image: product_image_url, category: "clothing", subcategory: "tops")

# When a shopper opens live try-on. Render `start` to the browser as-is (e.g. `render json: start`):
start = client.start_live_session(
  garment_id: garment["id"],
  end_user_id: shopper.id.to_s,                # one stream per end user
  allowed_origin: "https://shop.example.com"   # locks the media token to your site
)

client.get_live_session(start["session"]["id"])   # { "status" => ..., "seconds" => ..., "creditsCharged" => ... }
client.stop_live_session(start["session"]["id"])  # end it from your server
client.get_live_config                            # { "enabled" => ..., "secondsPerCredit" => ..., "maxSeconds" => ... }
```

Billing is per `secondsPerCredit` seconds of streamed video, from the first try-on frame. Garment switches during a
session are free.

`prepare_live_garment` also takes optional overrides:

```ruby
client.prepare_live_garment(
  garment_image: product_image_url,
  category: "footwear",
  detail_images: [side_view_url, back_view_url],           # up to 3 extra views; they only sharpen the description
  description: "black leather knee-high boots",            # your description (max 200), used in the generated prompt
  instructions: "Replace only the shoes with the boots.",  # or your own prompt (max 1000), used verbatim
  enhance_prompt: false                                    # keep the prompt as-is (default true)
)
```

### Outfits

Combine 2–3 prepared garments into one outfit worn together. The outfit's `"id"` works wherever a garment id does
(`start_live_session`, the browser's `switchGarment`). To swap one item, prepare the new combination (cached) and switch to it.

```ruby
top      = client.prepare_live_garment(garment_image: shirt_url, category: "clothing", subcategory: "tops")
trousers = client.prepare_live_garment(garment_image: trousers_url, category: "clothing", subcategory: "bottoms")
shoes    = client.prepare_live_garment(garment_image: shoes_url, category: "footwear")

outfit = client.prepare_live_outfit(garment_ids: [top["id"], trousers["id"], shoes["id"]])
# outfit["category"] == "outfit", outfit["items"] = the garment ids top to bottom
start = client.start_live_session(garment_id: outfit["id"], end_user_id: shopper.id.to_s)

# Later the shopper picks another top: prepare that outfit and switch the running stream to it.
jacket = client.prepare_live_garment(garment_image: jacket_url, category: "clothing", subcategory: "tops")
next_outfit = client.prepare_live_outfit(garment_ids: [jacket["id"], trousers["id"], shoes["id"]])
# Send next_outfit["id"] to the browser, which switches with tryiton-live: await live.switchGarment(id);
```

`prepare_live_outfit` also takes `instructions:` and `enhance_prompt:`, as above.

## Error handling

All failures raise `Tryiton::Error`, which carries the HTTP status code and the API error name.

```ruby
begin
  client.try_on_fashion(...)
rescue Tryiton::Error => e
  puts "#{e.status} #{e.error_name} #{e.message}" # e.g. 429 OutOfCredits
end
```

## Notes

- Output image URLs expire 72 hours after completion. Download any results you want to keep.
- Failed jobs are never charged.
- Every request sends `User-Agent: tryiton-ruby/<version>`.
- Type signatures (RBS) ship in `sig/` for Steep and other RBS tooling.
- To route requests through your own HTTP layer (retries, logging, a proxy), pass `transport:` to `Client.new`: any
  object whose `call(request)` takes a `Tryiton::Request` and returns something with `status` and `body`. See
  `Tryiton::NetHTTPTransport` for the default.

## Development

```bash
bundle install
bundle exec rake test               # Minitest, including the shared contract cases
bundle exec rbs -I sig validate     # RBS signatures (Ruby 3.1+)
```

`test/fixtures/sdk-cases.json` is generated from the TryItOn backend's API contract. Don't edit it here.

## Documentation

Full documentation, parameter reference, and guides: [docs.tryiton.now](https://docs.tryiton.now)

## License

MIT
