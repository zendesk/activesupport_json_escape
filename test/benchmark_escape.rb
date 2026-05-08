require "minitest/autorun"
require "minitest/benchmark"
require_relative "../lib/activesupport_json_escape"

class EscapeBenchmark < Minitest::Benchmark
  SIZES = [1024, 4096, 16384, 65536].freeze
  INNER_ITERATIONS = 1000

  HTML_UNIT = "<p>foo & bar</p>"          # 16 bytes, 4 escapable
  MIXED_UNIT = "the quick brown fox jumps over &"  # 32 bytes, 1 escapable

  def self.bench_range
    SIZES
  end

  def bench_clean_string
    assert_performance_linear 0.99 do |n|
      payload = "a" * n
      encode(payload)
    end
  end

  def bench_mixed_string
    assert_performance_linear 0.99 do |n|
      payload = MIXED_UNIT * (n / MIXED_UNIT.bytesize)
      encode(payload)
    end
  end

  def bench_html_string
    assert_performance_linear 0.99 do |n|
      payload = HTML_UNIT * (n / HTML_UNIT.bytesize)
      encode(payload)
    end
  end

  private

  def encode(payload)
    encoder = ActiveSupportJsonEscape::Encoder.new(escape: true)
    INNER_ITERATIONS.times { encoder.encode(payload) }
  end
end
