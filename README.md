# activesupport_json_escape

A drop-in replacement for `ActiveSupport::JSON::Encoding::JSONGemEncoder` that
moves the HTML-entity and JS-separator escaping step from Ruby `gsub!` calls
into a C extension.

It does **not** re-implement general JSON encoding. It subclasses
ActiveSupport's encoder, delegates serialization to the standard `json` gem,
and only takes over the final escape pass. It also provides one narrow native
primitive for legacy systems that must quote arbitrary bytes.

## Installation

Add to your Gemfile:

```ruby
gem "activesupport_json_escape"
```

## Usage

Register the encoder once, at application boot:

```ruby
require "activesupport_json_escape"

ActiveSupport.json_encoder = ActiveSupportJsonEscape::Encoder
```

After that, existing callers of `ActiveSupport::JSON.encode(...)` and
`Object#to_json` are automatically routed through this encoder. No call-site
changes are needed.

## Quoting arbitrary bytes

`ActiveSupportJsonEscape.quote_json_bytes(string)` returns one complete JSON
string token, including its surrounding double quotes. It reads the input as
bytes without validation or transcoding:

```ruby
input = "body:\xff\n".b.force_encoding(Encoding::UTF_8)
quoted = ActiveSupportJsonEscape.quote_json_bytes(input)

quoted.bytes
# => [34, 98, 111, 100, 121, 58, 255, 92, 110, 34]
quoted.encoding
# => Encoding::ASCII_8BIT
```

The method escapes `"`, `\\`, and bytes `0x00..0x1f` as JSON requires. It uses
the short escapes `\b`, `\f`, `\n`, `\r`, and `\t`; other control bytes use
lowercase `\u00xx`. All other bytes are copied unchanged. In particular, `/`,
`<`, `>`, `&`, U+2028, U+2029, and malformed non-control bytes are not changed.
The input is never mutated, including when it is frozen or has a non-binary
encoding. Non-String arguments raise `TypeError`; objects with `to_str` are not
coerced.

The result is always `ASCII-8BIT`. This is deliberate: copied bytes may not be
valid UTF-8, so labeling the result as UTF-8 would be misleading.

> **Warning:** output containing malformed UTF-8 is not a standards-compliant
> JSON document. This API exists only to preserve byte-for-byte behavior of
> legacy `Oj.dump` call sites. For new formats, require valid UTF-8, replace
> malformed sequences explicitly, or encode binary data with Base64.

With `json` 2.21.1, a `JSON::Fragment` lets the normal generator serialize the
surrounding structure while this method handles a malformed string value:

```ruby
coder = JSON::Coder.new do |value, is_key|
  if value.is_a?(String) && !value.valid_encoding?
    JSON::Fragment.new(
      ActiveSupportJsonEscape.quote_json_bytes(value)
    )
  else
    value.as_json
  end
end

document = coder.dump({"parts" => ["text", malformed_attachment_body]})
```

The callback has two arguments, `(value, is_key)`. There is a `json` 2.21.1
key limitation: malformed native `String` hash keys currently reach this
callback with `is_key == false`, and the generator then rejects the returned
`JSON::Fragment` because fragments cannot be object keys. Use this technique
for malformed values, not malformed keys. Non-string keys do receive
`is_key == true`.

## Configuration

All configuration continues to happen on ActiveSupport:

```ruby
ActiveSupport::JSON::Encoding.escape_html_entities_in_json = true  # default
ActiveSupport::JSON::Encoding.escape_js_separators_in_json = true  # default
ActiveSupport::JSON::Encoding.use_standard_json_time_format = true # default
ActiveSupport::JSON::Encoding.time_precision = 3                   # default
```

Per-call options (`:escape`, `:escape_html_entities`) behave identically to
ActiveSupport's encoder.

## Compatibility

Output is byte-for-byte identical to
`ActiveSupport::JSON::Encoding::JSONGemEncoder` for the same input and
configuration. The test suite verifies this by running both encoders on the
same fixtures.

Supported versions are:

- Ruby 3.2 or newer.
- ActiveSupport 8.1.x.
- `json` 2.21 through 2.x. The next major version is excluded until its
  compatibility is known.

The encoder directly subclasses ActiveSupport 8.1's `JSONGemCoderEncoder` and
uses its `CODER`, `@options`, and `@escape` behavior. The test suite compares
its output byte-for-byte with the stock encoder.

This gem already requires its C extension on every supported platform, so
`quote_json_bytes` has no pure-Ruby fallback.

## When this is worth installing

- High-volume JSON encoding where payloads commonly contain `<`, `>`, `&`, or
  the U+2028 / U+2029 separators — e.g., API responses with user-generated
  content.

## When it isn't worth installing

- Payloads rarely contain characters that need escaping.
- HTML-entity escaping is already disabled
  (`escape_html_entities_in_json = false`) and JS-separator escaping isn't in
  use either.
- The JSON is never interpolated into a `<script>` tag, in which case
  HTML-entity escaping serves no purpose.
- All consuming browsers support the [JSON superset of
  ECMAScript](https://caniuse.com/mdn-javascript_builtins_json_json_superset),
  in which case U+2028 / U+2029 escaping is unnecessary.

In those cases, the escape pass is already cheap in stock ActiveSupport, and
this gem adds little.

## Performance

The speedup is concentrated in the escape step. Benchmarks on a Ruby 3.4 build
with YJIT show roughly 3x faster HTML/JS escaping than ActiveSupport's Ruby
implementation; encoding payloads with no escapable characters performs
comparably to stock. See `benchmark.rb` for the exact measurements on your
hardware.

## Development

```bash
bundle install
bundle exec rake compile
bundle exec rake test
```

To check for C-level memory leaks (requires valgrind):

```bash
bundle exec rake test:valgrind
```

## Copyright and license

Copyright 2026 Zendesk, Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
