## [Unreleased]

- Accelerate the escape sizing pass with a NEON vector scan on AArch64,
  falling back to the existing scalar scan on other architectures. Only the
  byte-counting pass is vectorized; the escape output is unchanged and verified
  byte-for-byte against the scalar path. Set `ASJE_DISABLE_SIMD=1` at build
  time to force the scalar scan.

## [0.1.0] - 2026-05-08

- Initial release
