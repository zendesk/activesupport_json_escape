## [Unreleased]

- Add `ActiveSupportJsonEscape.quote_json_bytes`, a native byte-preserving JSON
  string-token quoter compatible with compact `Oj.dump` string output,
  including malformed UTF-8 bytes. Its sizing pass uses NEON on AArch64 and a
  portable scalar fallback elsewhere.
- Require `json` 2.21 through 2.x for
  `JSONGemCoderEncoder`, `JSON::Coder`, and malformed-string callbacks.

## [0.1.0] - 2026-05-08

- Initial release
