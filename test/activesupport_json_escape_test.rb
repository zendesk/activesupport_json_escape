require "minitest/autorun"
require "active_support"
require "active_support/json"
require "activesupport_json_escape"

ActiveSupport.json_encoder = ActiveSupportJsonEscape::Encoder

class ActiveSupportJsonEscapeTest < Minitest::Test
  def test_encode_simple_hash
    result = ActiveSupport::JSON.encode({a: 1, b: 2})
    assert_equal '{"a":1,"b":2}', result
  end

  def test_encode_array
    result = ActiveSupport::JSON.encode([1, 2, 3])
    assert_equal "[1,2,3]", result
  end

  def test_encode_string
    result = ActiveSupport::JSON.encode("hello")
    assert_equal '"hello"', result
  end

  def test_encode_nested_structure
    data = {
      users: [
        {name: "Alice", age: 30},
        {name: "Bob", age: 25}
      ]
    }
    result = ActiveSupport::JSON.encode(data)
    assert_includes result, "Alice"
    assert_includes result, "Bob"
  end

  def test_html_entity_escaping
    # By default, HTML entities should be escaped
    result = ActiveSupport::JSON.encode({html: "<script>"})
    assert_includes result, "\\u003c"
    assert_includes result, "\\u003e"
  end

  def test_js_separator_escaping
    # By default, U+2028 and U+2029 should be escaped
    result = ActiveSupport::JSON.encode({text: "line separator"})
    assert_includes result, "\\u2028"
  end

  def test_disable_html_entity_escaping
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = false
    result = ActiveSupport::JSON.encode({html: "<script>"})
    refute_includes result, "\\u003c"
  ensure
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = true
  end

  def test_disable_escape_option
    result = ActiveSupport::JSON.encode({html: "<script>"}, escape: false)
    refute_includes result, "\\u003c"
  end

  def test_non_string_hash_keys
    result = ActiveSupport::JSON.encode({1 => "one", 2 => "two"})
    assert_includes result, '"1"'
    assert_includes result, '"2"'
  end

  def test_symbol_keys
    result = ActiveSupport::JSON.encode({name: "test", value: 123})
    assert_includes result, '"name"'
    assert_includes result, '"value"'
  end

  def test_nil_value
    result = ActiveSupport::JSON.encode(nil)
    assert_equal "null", result
  end

  def test_boolean_values
    assert_equal "true", ActiveSupport::JSON.encode(true)
    assert_equal "false", ActiveSupport::JSON.encode(false)
  end

  def test_numeric_values
    assert_equal "42", ActiveSupport::JSON.encode(42)
    assert_equal "3.14", ActiveSupport::JSON.encode(3.14)
  end

  def test_as_json_method
    obj = Object.new
    def obj.as_json(options = nil)
      {custom: "representation"}
    end

    result = ActiveSupport::JSON.encode(obj)
    assert_includes result, "custom"
    assert_includes result, "representation"
  end

  def test_compatibility_with_activesupport
    # Test that our implementation produces the same output as ActiveSupport's
    # default JSONGemEncoder when swapped in via ActiveSupport.json_encoder.
    data = {
      string: "hello",
      number: 42,
      float: 3.14,
      html: "<script>alert('xss')</script>",
      unicode: "line separator",
      nested: {
        array: [1, 2, 3],
        bool: true
      }
    }

    fast_result = ActiveSupport::JSON.encode(data)

    begin
      ActiveSupport.json_encoder = ActiveSupport::JSON::Encoding::JSONGemEncoder
      as_result = ActiveSupport::JSON.encode(data)
    ensure
      ActiveSupport.json_encoder = ActiveSupportJsonEscape::Encoder
    end

    assert_equal as_result, fast_result
    assert_includes fast_result, "\\u003c"  # HTML entities escaped
    assert_includes fast_result, "\\u003e"
    assert_includes fast_result, "\\u2028"  # JS separators escaped
  end
end
