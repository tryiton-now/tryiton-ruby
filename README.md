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
job_id = client.try_on_clothes(
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

`try_on_clothes` covers clothing and accessory try-on. The most important parameters:

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

# Tattoo try-on
client.try_on_tattoo(body_image: body_url, design_image: design_url, placement: "on the right forearm, small")

# Poll a job manually, or check your credit balance
status  = client.get_status(job_id)  # { "status" => ..., "output" => [...], "error" => ... }
credits = client.get_credits          # { "on_demand" => ..., "subscription" => ..., "purchased" => ..., "reserved" => ... }
```

## Error handling

All failures raise `Tryiton::Error`, which carries the HTTP status code and the API error name.

```ruby
begin
  client.try_on_clothes(...)
rescue Tryiton::Error => e
  puts "#{e.status} #{e.error_name} #{e.message}" # e.g. 429 OutOfCredits
end
```

## Notes

- Output image URLs expire 72 hours after completion. Download any results you want to keep.
- Failed jobs are never charged.

## Documentation

Full documentation, parameter reference, and guides: [docs.tryiton.now](https://docs.tryiton.now)

## License

MIT
