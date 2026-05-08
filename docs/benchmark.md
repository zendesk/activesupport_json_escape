Output from running benchmark.rb on a Macbook Pro M1:

```
ActiveSupportJsonEscape vs ActiveSupport::JSON Benchmark
============================================================

Simple hash:
ruby 3.2.9 (2025-07-24 revision 8f611e0c46) [arm64-darwin24]
Warming up --------------------------------------
ActiveSupportJsonEscape   213.348k i/100ms
    ActiveSupport::JSON    78.511k i/100ms
Calculating -------------------------------------
ActiveSupportJsonEscape      2.218M (± 1.9%) i/s  (450.94 ns/i) -     11.094M in   5.004677s
    ActiveSupport::JSON    782.523k (± 1.4%) i/s    (1.28 μs/i) -      3.926M in   5.017476s

Comparison:
ActiveSupportJsonEscape:  2217570.8 i/s
    ActiveSupport::JSON:   782522.8 i/s - 2.83x  slower


Nested data:
ruby 3.2.9 (2025-07-24 revision 8f611e0c46) [arm64-darwin24]
Warming up --------------------------------------
ActiveSupportJsonEscape    95.396k i/100ms
    ActiveSupport::JSON    18.441k i/100ms
Calculating -------------------------------------
ActiveSupportJsonEscape    949.572k (± 4.1%) i/s    (1.05 μs/i) -      4.770M in   5.033785s
    ActiveSupport::JSON    185.016k (± 2.2%) i/s    (5.40 μs/i) -    940.491k in   5.085779s

Comparison:
ActiveSupportJsonEscape:   949572.3 i/s
    ActiveSupport::JSON:   185016.3 i/s - 5.13x  slower


Large array (100 objects):
ruby 3.2.9 (2025-07-24 revision 8f611e0c46) [arm64-darwin24]
Warming up --------------------------------------
ActiveSupportJsonEscape     2.833k i/100ms
    ActiveSupport::JSON   477.000 i/100ms
Calculating -------------------------------------
ActiveSupportJsonEscape     27.654k (± 3.7%) i/s   (36.16 μs/i) -    138.817k in   5.027181s
    ActiveSupport::JSON      4.710k (± 1.9%) i/s  (212.30 μs/i) -     23.850k in   5.065025s

Comparison:
ActiveSupportJsonEscape:    27654.4 i/s
    ActiveSupport::JSON:     4710.4 i/s - 5.87x  slower


HTML escaping:
ruby 3.2.9 (2025-07-24 revision 8f611e0c46) [arm64-darwin24]
Warming up --------------------------------------
ActiveSupportJsonEscape   127.167k i/100ms
    ActiveSupport::JSON    21.779k i/100ms
Calculating -------------------------------------
ActiveSupportJsonEscape      1.292M (± 4.1%) i/s  (774.26 ns/i) -      6.486M in   5.030695s
    ActiveSupport::JSON    215.998k (± 2.8%) i/s    (4.63 μs/i) -      1.089M in   5.045590s

Comparison:
ActiveSupportJsonEscape:  1291559.3 i/s
    ActiveSupport::JSON:   215998.2 i/s - 5.98x  slower


============================================================
Verification that outputs match:
Simple: true
Nested: true
Large: true
HTML: true
```
