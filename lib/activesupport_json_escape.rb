require "active_support"
require "active_support/json/encoding"

require_relative "activesupport_json_escape/version"
require_relative "activesupport_json_escape/activesupport_json_escape"

module ActiveSupportJsonEscape
  class Encoder < ::ActiveSupport::JSON::Encoding::JSONGemCoderEncoder
    def encode(value)
      value = value.as_json(@options) unless @options.empty?

      json = CODER.dump(value)

      return json unless @escape

      encoding = ::ActiveSupport::JSON::Encoding
      json.force_encoding(::Encoding::BINARY)
      if @options.fetch(:escape_html_entities, encoding.escape_html_entities_in_json)
        if encoding.escape_js_separators_in_json
          ::ActiveSupportJsonEscape.escape_full!(json)
        else
          ::ActiveSupportJsonEscape.escape_html_entities!(json)
        end
      elsif encoding.escape_js_separators_in_json
        ::ActiveSupportJsonEscape.escape_js_separators!(json)
      end
      json.force_encoding(::Encoding::UTF_8)
    end
  end
end
