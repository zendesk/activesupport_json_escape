require "bundler/setup"
require "benchmark/ips"
require "active_support"
require "active_support/json"
require_relative "lib/activesupport_json_escape"

# Test data
simple_data = {name: "Alice", age: 30, email: "alice@example.com"}

nested_data = {
  users: [
    {id: 1, name: "Alice", email: "alice@example.com", active: true},
    {id: 2, name: "Bob", email: "bob@example.com", active: false},
    {id: 3, name: "Charlie", email: "charlie@example.com", active: true}
  ],
  metadata: {
    total: 3,
    page: 1,
    per_page: 10
  }
}

large_data = {
  users: Array.new(100) do |i|
    {
      id: i,
      name: "User #{i}",
      email: "user#{i}@example.com",
      active: i.even?,
      score: i * 3.14,
      tags: ["tag#{i}", "tag#{i + 1}"]
    }
  end
}

html_data = {
  content: "<script>alert('xss')</script>",
  body: "<div>Hello & goodbye</div>",
  title: "Test > Production"
}

fast = ActiveSupportJsonEscape::Encoder.new
stock = ActiveSupport::JSON::Encoding::JSONGemEncoder.new

puts "ActiveSupportJsonEscape vs ActiveSupport::JSON Benchmark"
puts "=" * 60
puts

puts "Simple hash:"
Benchmark.ips do |x|
  x.report("ActiveSupportJsonEscape") { fast.encode(simple_data) }
  x.report("ActiveSupport::JSON") { stock.encode(simple_data) }
  x.compare!
end

puts "\nNested data:"
Benchmark.ips do |x|
  x.report("ActiveSupportJsonEscape") { fast.encode(nested_data) }
  x.report("ActiveSupport::JSON") { stock.encode(nested_data) }
  x.compare!
end

puts "\nLarge array (100 objects):"
Benchmark.ips do |x|
  x.report("ActiveSupportJsonEscape") { fast.encode(large_data) }
  x.report("ActiveSupport::JSON") { stock.encode(large_data) }
  x.compare!
end

puts "\nHTML escaping:"
Benchmark.ips do |x|
  x.report("ActiveSupportJsonEscape") { fast.encode(html_data) }
  x.report("ActiveSupport::JSON") { stock.encode(html_data) }
  x.compare!
end

puts "\n" + "=" * 60
puts "Verification that outputs match:"
puts "Simple: #{fast.encode(simple_data) == stock.encode(simple_data)}"
puts "Nested: #{fast.encode(nested_data) == stock.encode(nested_data)}"
puts "Large: #{fast.encode(large_data) == stock.encode(large_data)}"
puts "HTML: #{fast.encode(html_data) == stock.encode(html_data)}"
