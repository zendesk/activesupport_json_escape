require "minitest/autorun"
require "active_support"
require "active_support/json"
require "activesupport_json_escape"

# The SIMD sizing scan must produce output byte-for-byte identical to a plain
# scalar reference across every alignment relative to the 16-byte vector width.
# A wrong count would mis-size the result buffer, so this exercises the escape
# bytes at every offset within and straddling chunk boundaries.
class EscapeSizingTest < Minitest::Test
  M = ActiveSupportJsonEscape

  # Independent Ruby reference. Mirrors do_escape's contract without any of the
  # C sizing logic, so a divergence points at the counting pass.
  def reference(bytes, escape_html:, escape_js:)
    out = +"".b
    i = 0
    while i < bytes.length
      c = bytes[i]
      if escape_html && (c == 0x3c || c == 0x3e || c == 0x26)
        out << {0x3c => "\\u003c", 0x3e => "\\u003e", 0x26 => "\\u0026"}.fetch(c)
        i += 1
        next
      end
      if escape_js && c == 0xE2 && i + 2 < bytes.length && bytes[i + 1] == 0x80 &&
          (bytes[i + 2] == 0xA8 || bytes[i + 2] == 0xA9)
        out << ((bytes[i + 2] == 0xA8) ? "\\u2028" : "\\u2029")
        i += 3
        next
      end
      out << c
      i += 1
    end
    out
  end

  def call(name, str)
    dup = str.b
    result = M.public_send(name, dup)
    # Bang methods return nil (unchanged) when nothing needed escaping.
    result.nil? ? str.b : dup
  end

  MODES = {
    escape_full!: {escape_html: true, escape_js: true},
    escape_html_entities!: {escape_html: true, escape_js: false},
    escape_js_separators!: {escape_html: false, escape_js: true}
  }.freeze

  # Bytes that trigger each rule plus neutral filler and near-miss JS prefixes.
  ESCAPABLE = [0x3c, 0x3e, 0x26].freeze
  JS_SEQ = [0xE2, 0x80, 0xA8].freeze
  JS_SEQ2 = [0xE2, 0x80, 0xA9].freeze
  NEAR_MISS = [0xE2, 0x80, 0x00, 0xE2, 0x81, 0xA8].freeze # valid prefix, wrong 3rd byte

  def assert_matches(bytes)
    str = bytes.pack("C*")
    MODES.each do |name, opts|
      expected = reference(bytes, **opts)
      assert_equal expected, call(name, str),
        "#{name} mismatch for bytes #{bytes.inspect}"
    end
  end

  def test_all_lengths_of_plain_bytes_around_chunk_boundaries
    (0..40).each do |len|
      assert_matches(Array.new(len) { |i| 0x61 + (i % 26) })
    end
  end

  def test_single_escape_byte_at_every_offset
    ESCAPABLE.each do |byte|
      (0..40).each do |offset|
        bytes = Array.new(40, 0x61)
        bytes[offset] = byte
        assert_matches(bytes)
      end
    end
  end

  def test_js_sequence_at_every_offset_including_straddling_boundaries
    [JS_SEQ, JS_SEQ2].each do |seq|
      (0..37).each do |offset|
        bytes = Array.new(40, 0x61)
        seq.each_with_index { |b, k| bytes[offset + k] = b }
        assert_matches(bytes)
      end
    end
  end

  def test_js_sequence_truncated_at_end
    # 0xE2 0x80 with no third byte, and 0xE2 alone, at the tail.
    assert_matches(Array.new(30, 0x61) + [0xE2, 0x80])
    assert_matches(Array.new(31, 0x61) + [0xE2])
    assert_matches(Array.new(16, 0x61) + [0xE2, 0x80])
  end

  def test_near_miss_js_prefixes_are_not_counted
    (0..34).each do |offset|
      bytes = Array.new(40, 0x61)
      NEAR_MISS.each_with_index { |b, k| bytes[offset + k] = b }
      assert_matches(bytes)
    end
  end

  def test_dense_mixed_escapes
    unit = [0x3c, 0x62, 0x26, 0xE2, 0x80, 0xA8, 0x3e, 0xE2, 0x80, 0xA9]
    (1..8).each do |reps|
      assert_matches(unit * reps)
    end
  end

  def test_adjacent_and_overlapping_candidates
    # 0xE2 0x80 0xA8 immediately followed by another sequence, and HTML bytes
    # packed against JS sequences with no filler between.
    assert_matches([0xE2, 0x80, 0xA8, 0xE2, 0x80, 0xA9] * 4)
    assert_matches([0x3c, 0x3e, 0x26] * 8)
    assert_matches([0x3c, 0xE2, 0x80, 0xA8, 0x3e, 0xE2, 0x80, 0xA9] * 3)
  end

  def test_large_payload_exact_size
    bytes = ([0x61] * 100 + [0x3c] + [0x62] * 50 + JS_SEQ) * 500
    assert_matches(bytes)
  end
end
