# Measures the isolated escape sizing+write pass, the part this gem's C
# extension owns. Run once per build to compare the NEON and scalar sizing
# scans:
#
#   bundle exec rake clean && bundle exec rake compile
#   bundle exec ruby -Ilib test/benchmark_escape_scan.rb                 # NEON
#
#   bundle exec rake clean && ASJE_DISABLE_SIMD=1 bundle exec rake compile
#   bundle exec ruby -Ilib test/benchmark_escape_scan.rb                 # scalar
#
# Reports min-of-trials ns/op; absolute numbers are only comparable within the
# same quiet machine, so treat the NEON-vs-scalar ratio as the signal.

require "active_support"
require "active_support/json"
require "activesupport_json_escape"

M = ActiveSupportJsonEscape

def time(iters)
  GC.start
  GC.disable
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  iters.times { yield }
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  GC.enable
  (t1 - t0) * 1e9 / iters
end

def best(trials, iters, &blk)
  Array.new(trials) { time(iters, &blk) }.min
end

# Clean input takes the no-escape fast path: do_escape scans, finds nothing,
# and returns without allocating. The whole cost is the sizing scan, so this is
# where a faster scan shows up most directly. The bang methods do not mutate in
# that case, so a single frozen binary buffer can be reused across iterations.
def clean(size)
  ("the quick brown fox " * (size / 20 + 2))[0, size].b
end

# Escape-heavy input pays for the scan plus allocation and the (scalar) write
# pass; the scan is a smaller share here.
def htmlish(size)
  ("<div>a & b</div> " * (size / 17 + 2))[0, size].b
end

puts "arch: #{RUBY_PLATFORM}   ruby: #{RUBY_VERSION}"
puts "(build: run once with NEON, once with ASJE_DISABLE_SIMD=1)"
puts

[256, 4096, 65_536].each do |size|
  c = clean(size)
  h = htmlish(size)
  iters = (size >= 65_536) ? 50_000 : 500_000

  full_clean = best(9, iters) { M.escape_full!(c) }
  html_clean = best(9, iters) { M.escape_html_entities!(c) }
  js_clean = best(9, iters) { M.escape_js_separators!(c) }
  full_html = best(9, iters) { M.escape_full!(h.dup) }

  printf("[%6dB]\n", size)
  printf("  escape_full!          clean:  %9.1f ns  (%.2f GB/s)\n", full_clean, size / full_clean)
  printf("  escape_html_entities! clean:  %9.1f ns\n", html_clean)
  printf("  escape_js_separators! clean:  %9.1f ns\n", js_clean)
  printf("  escape_full!        htmlish:  %9.1f ns  (incl. alloc+write)\n", full_html)
  puts
end
