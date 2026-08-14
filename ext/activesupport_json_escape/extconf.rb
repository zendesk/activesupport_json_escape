require "mkmf"

# Setting ASJE_DISABLE_SIMD=1 forces the portable scalar sizing path even on
# architectures that would otherwise use SIMD. CI uses this to exercise the
# fallback on the same hosts that have vector support.
if ENV["ASJE_DISABLE_SIMD"] == "1"
  append_cflags("-DASJE_DISABLE_SIMD")
end

create_makefile("activesupport_json_escape/activesupport_json_escape")
