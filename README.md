# activesupport_json_escape

A drop-in replacement for `ActiveSupport::JSON::Encoding::JSONGemEncoder` that
moves the HTML-entity and JS-separator escaping step from Ruby `gsub!` calls
into a C extension.

It does **not** re-implement JSON encoding. It subclasses ActiveSupport's
encoder, delegates serialization to the standard `json` gem (the same `CODER`
ActiveSupport uses), and only takes over the final escape pass.

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

## Configuration

All configuration continues to happen on ActiveSupport:

```ruby
ActiveSupport::JSON::Encoding.escape_html_entities_in_json = true  # default
ActiveSupport::JSON::Encoding.escape_js_separators_in_json = true  # default
ActiveSupport::JSON::Encoding.use_standard_json_time_format = true # default
ActiveSupport::JSON::Encoding.time_precision = 3                   # default
```

Per-call options (`:escape`, `:escape_html_entities`) also behave identically
to ActiveSupport's encoder.

## Compatibility

Output is byte-for-byte identical to
`ActiveSupport::JSON::Encoding::JSONGemEncoder` for the same input and
configuration. The test suite verifies this by running both encoders on the
same fixtures.

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
