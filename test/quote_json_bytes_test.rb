require "minitest/autorun"
require "active_support"
require "active_support/json"
require "json"
require "activesupport_json_escape"

class QuoteJsonBytesTest < Minitest::Test
  NAMED_ESCAPES = {
    0x08 => "\\b",
    0x09 => "\\t",
    0x0a => "\\n",
    0x0c => "\\f",
    0x0d => "\\r"
  }.freeze

  def test_empty_string
    assert_quote '""', ""
  end

  def test_ordinary_ascii
    assert_quote '"hello, world!"', "hello, world!"
  end

  def test_quotes_and_backslashes
    assert_quote '"say \\"hello\\" with \\\\slashes"', 'say "hello" with \\slashes'
  end

  def test_named_control_escapes
    assert_quote '"\\b\\f\\n\\r\\t"', "\b\f\n\r\t"
  end

  def test_every_control_byte
    0x20.times do |byte|
      escaped = NAMED_ESCAPES.fetch(byte) { format("\\u%04x", byte) }
      assert_quote "\"#{escaped}\"", byte.chr(Encoding::BINARY)
    end
  end

  def test_slash_is_not_escaped
    assert_quote '"https://example.test/a/b"', "https://example.test/a/b"
  end

  def test_valid_multibyte_utf8_is_copied_byte_for_byte
    input = "Héllø 世界 😀"
    assert_quote "\"#{input}\"".b, input
  end

  def test_non_utf8_encoding_is_processed_as_bytes
    input = "\xe9".b.force_encoding(Encoding::ISO_8859_1)
    assert_quote "\"\xe9\"".b, input
  end

  def test_javascript_separators_are_not_escaped
    assert_quote "\"\u2028\u2029\"".b, "\u2028\u2029"
  end

  def test_html_characters_are_not_escaped
    assert_quote '"<p>one & two</p>"', "<p>one & two</p>"
  end

  def test_malformed_bytes_are_copied
    inputs = [
      "\x80".b.force_encoding(Encoding::UTF_8),
      "\xff".b.force_encoding(Encoding::UTF_8),
      "\xe2\x82".b.force_encoding(Encoding::UTF_8),
      "before\xc0\xafmiddle\xffafter".b.force_encoding(Encoding::UTF_8)
    ]

    inputs.each do |input|
      assert_quote('"'.b + input.b + '"'.b, input)
    end
  end

  def test_embedded_nul
    assert_quote '"before\\u0000after"', "before\0after"
  end

  def test_frozen_input_is_accepted_and_not_mutated
    input = "frozen\n\xff".b.force_encoding(Encoding::UTF_8).freeze
    original_bytes = input.bytes
    original_encoding = input.encoding

    result = ActiveSupportJsonEscape.quote_json_bytes(input)

    assert_equal '"frozen\\n'.b + "\xff".b + '"'.b, result
    assert_equal original_bytes, input.bytes
    assert_equal original_encoding, input.encoding
    assert_predicate input, :frozen?
  end

  def test_mutable_input_is_not_changed
    input = "a\"b\n\xff".b.force_encoding(Encoding::UTF_8)
    original = input.dup

    ActiveSupportJsonEscape.quote_json_bytes(input)

    assert_equal original.bytes, input.bytes
    assert_equal original.encoding, input.encoding
  end

  def test_non_string_input_is_rejected_without_to_str_coercion
    string_like = Object.new
    def string_like.to_str = "string-like"

    [nil, 123, :symbol, string_like].each do |input|
      assert_raises(TypeError) { ActiveSupportJsonEscape.quote_json_bytes(input) }
    end
  end

  def test_large_string
    input = ("abc\0\"\\\n\xff".b * 150_000).force_encoding(Encoding::UTF_8)
    expected_unit = "abc\\u0000\\\"\\\\\\n\xff".b

    assert_quote('"'.b + (expected_unit * 150_000) + '"'.b, input)
  end

  def test_matches_reference_implementation_byte_for_byte
    inputs = [
      "",
      "plain / <>&",
      "\"\\\b\f\n\r\t",
      (0x00..0x1f).to_a.pack("C*"),
      "\u2028\u2029",
      "valid UTF-8: café 世界",
      "malformed: \x80 \xff \xe2\x82".b.force_encoding(Encoding::UTF_8)
    ]

    inputs.each do |input|
      assert_equal reference_quote_json_bytes(input), ActiveSupportJsonEscape.quote_json_bytes(input)
    end
  end

  def test_matches_reference_for_every_byte_in_one_vectorized_input
    input = (0x00..0xff).to_a.pack("C*").force_encoding(Encoding::UTF_8)

    assert_equal reference_quote_json_bytes(input), ActiveSupportJsonEscape.quote_json_bytes(input)
  end

  def test_matches_reference_across_vector_chunk_boundaries
    pattern = [0x00, 0x08, 0x09, 0x0a, 0x0c, 0x0d, 0x1f, 0x20, 0x22, 0x2f, 0x5c, 0x7f, 0x80, 0xff]

    [15, 16, 17, 31, 32, 33].each do |length|
      input = pattern.cycle.take(length).pack("C*").force_encoding(Encoding::UTF_8)
      assert_equal reference_quote_json_bytes(input), ActiveSupportJsonEscape.quote_json_bytes(input)
    end
  end

  def test_fragment_serializes_a_malformed_nested_value_and_parser_round_trips_it
    malformed = "attachment:\x00\xff\xe2\x82:end".b.force_encoding(Encoding::UTF_8)
    coder = malformed_string_coder

    document = coder.dump({"message" => {"parts" => ["valid", malformed]}})
    parsed = JSON.parse(document)

    assert_equal malformed.bytes, parsed.fetch("message").fetch("parts").last.bytes
    refute_predicate document, :valid_encoding?
  end

  def test_malformed_native_string_key_is_reported_as_not_a_key_and_fragment_is_rejected
    malformed_key = "key:\xff".b.force_encoding(Encoding::UTF_8)
    callbacks = []
    coder = JSON::Coder.new do |value, is_key|
      callbacks << [value, is_key]
      if value.is_a?(String) && !value.valid_encoding?
        JSON::Fragment.new(ActiveSupportJsonEscape.quote_json_bytes(value))
      else
        value.as_json
      end
    end

    error = assert_raises(JSON::GeneratorError) { coder.dump({malformed_key => "value"}) }

    assert_match(/Fragment not allowed as object key/, error.message)
    malformed_callback = callbacks.find do |value, _is_key|
      value.is_a?(String) && value.bytes == malformed_key.bytes
    end
    refute_nil malformed_callback
    assert_equal false, malformed_callback.last
  end

  def test_non_string_hash_key_is_reported_as_a_key
    callbacks = []
    coder = JSON::Coder.new do |value, is_key|
      callbacks << [value, is_key]
      is_key ? value.to_s : value.as_json
    end

    assert_equal '{"123":"value"}', coder.dump({123 => "value"})
    assert_includes callbacks, [123, true]
  end

  private

  def assert_quote(expected, input)
    result = ActiveSupportJsonEscape.quote_json_bytes(input)
    assert_equal expected.b, result
    assert_equal Encoding::ASCII_8BIT, result.encoding
  end

  def malformed_string_coder
    JSON::Coder.new do |value, _is_key|
      if value.is_a?(String) && !value.valid_encoding?
        JSON::Fragment.new(ActiveSupportJsonEscape.quote_json_bytes(value))
      else
        value.as_json
      end
    end
  end

  def reference_quote_json_bytes(input)
    output = String.new('"', encoding: Encoding::BINARY)
    input.each_byte do |byte|
      escaped = case byte
      when 0x08 then "\\b"
      when 0x09 then "\\t"
      when 0x0a then "\\n"
      when 0x0c then "\\f"
      when 0x0d then "\\r"
      when 0x22 then '\\"'
      when 0x5c then "\\\\"
      else
        (byte < 0x20) ? format("\\u%04x", byte) : byte
      end
      output << escaped
    end
    output << '"'
  end
end
