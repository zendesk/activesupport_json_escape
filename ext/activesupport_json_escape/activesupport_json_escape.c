#include <ruby.h>
#include <ruby/encoding.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// SIMD sizing acceleration is opt-out via -DASJE_DISABLE_SIMD so CI can build
// and test the portable scalar fallback on the same hosts that have NEON.
#if !defined(ASJE_DISABLE_SIMD) && (defined(__aarch64__) || defined(_M_ARM64))
#include <arm_neon.h>
#define ASJE_HAVE_NEON 1
#endif

#ifdef ASJE_HAVE_NEON
// Count, over the 16 bytes at `p`, how many need HTML escaping (`<`, `>`, `&`)
// and how many begin a JS separator sequence (0xE2 0x80 0xA8/0xA9).
//
// The JS check reads up to two bytes past the 16-byte window via unaligned
// loads, so the caller must guarantee p[0..17] are all in bounds. HTML bytes
// and JS-sequence bytes are disjoint, and two JS sequences can never overlap
// (each requires distinct bytes at all three positions), so counting matches
// per start position yields exactly the same total as the scalar loop's
// advance-1-or-3 walk.
static inline void
count_escape_chunk_neon(const unsigned char *p, bool escape_html, bool escape_js,
                        long *html_count, long *js_count)
{
  uint8x16_t v0 = vld1q_u8(p);

  if (escape_html) {
    uint8x16_t html = vorrq_u8(
      vorrq_u8(vceqq_u8(v0, vdupq_n_u8('<')), vceqq_u8(v0, vdupq_n_u8('>'))),
      vceqq_u8(v0, vdupq_n_u8('&'))
    );
    // Each matching lane is 0xFF; mask to 1 before the horizontal add so the
    // 16-lane sum cannot exceed 16 and stays within a uint8 accumulator.
    *html_count += (long)vaddvq_u8(vandq_u8(html, vdupq_n_u8(1)));
  }

  if (escape_js) {
    uint8x16_t v1 = vld1q_u8(p + 1);
    uint8x16_t v2 = vld1q_u8(p + 2);
    uint8x16_t is_sep = vorrq_u8(
      vceqq_u8(v2, vdupq_n_u8(0xA8)),
      vceqq_u8(v2, vdupq_n_u8(0xA9))
    );
    uint8x16_t match = vandq_u8(
      vandq_u8(vceqq_u8(v0, vdupq_n_u8(0xE2)), vceqq_u8(v1, vdupq_n_u8(0x80))),
      is_sep
    );
    *js_count += (long)vaddvq_u8(vandq_u8(match, vdupq_n_u8(1)));
  }
}
#endif

static VALUE
do_escape(VALUE str, bool escape_html, bool escape_js)
{
  StringValue(str);
  rb_check_frozen(str);

  const char *src = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);

  long extra = 0;
  long i = 0;

#ifdef ASJE_HAVE_NEON
  if (escape_html || escape_js) {
    long html_count = 0;
    long js_count = 0;
    // The JS check peeks two bytes ahead, so only run the vector loop while a
    // full 16-byte chunk plus that two-byte lookahead stays in bounds. The
    // scalar loop below finishes the tail and any string shorter than that.
    for (; i + 18 <= len; i += 16) {
      count_escape_chunk_neon((const unsigned char *)src + i, escape_html, escape_js,
                              &html_count, &js_count);
    }
    extra += html_count * 5 + js_count * 3;
  }
#endif

  while (i < len) {
    unsigned char c = (unsigned char)src[i];
    if (escape_html && (c == '<' || c == '>' || c == '&')) {
      extra += 5;
      i++;
      continue;
    }
    if (escape_js && c == 0xE2 && i + 2 < len && (unsigned char)src[i + 1] == 0x80
      && ((unsigned char)src[i + 2] == 0xA8 || (unsigned char)src[i + 2] == 0xA9)) {
      extra += 3;
      i += 3;
      continue;
    }
    i++;
  }

  if (extra == 0) {
    return Qnil;
  }

  long result_len = len + extra;
  VALUE result = rb_str_buf_new(result_len);
  char *dst = RSTRING_PTR(result);

  // Allocation above may have triggered GC / compaction; re-fetch src.
  src = RSTRING_PTR(str);

  long out = 0;
  i = 0;
  while (i < len) {
    unsigned char c = (unsigned char)src[i];
    if (escape_html && c == '<') {
      memcpy(dst + out, "\\u003c", 6);
      out += 6;
      i++;
      continue;
    }
    if (escape_html && c == '>') {
      memcpy(dst + out, "\\u003e", 6);
      out += 6;
      i++;
      continue;
    }
    if (escape_html && c == '&') {
      memcpy(dst + out, "\\u0026", 6);
      out += 6;
      i++;
      continue;
    }
    if (escape_js && c == 0xE2 && i + 2 < len && (unsigned char)src[i + 1] == 0x80) {
      unsigned char c3 = (unsigned char)src[i + 2];
      if (c3 == 0xA8) {
        memcpy(dst + out, "\\u2028", 6);
        out += 6;
        i += 3;
        continue;
      }
      if (c3 == 0xA9) {
        memcpy(dst + out, "\\u2029", 6);
        out += 6;
        i += 3;
        continue;
      }
    }
    dst[out++] = src[i++];
  }

  rb_str_set_len(result, result_len);
  rb_enc_associate(result, rb_enc_get(str));
  rb_str_replace(str, result);
  return str;
}

static VALUE
escape_full_bang(VALUE self, VALUE str)
{
  return do_escape(str, true, true);
}

static VALUE
escape_html_entities_bang(VALUE self, VALUE str)
{
  return do_escape(str, true, false);
}

static VALUE
escape_js_separators_bang(VALUE self, VALUE str)
{
  return do_escape(str, false, true);
}

void
Init_activesupport_json_escape(void)
{
  VALUE m = rb_define_module("ActiveSupportJsonEscape");
  rb_define_singleton_method(m, "escape_full!", escape_full_bang, 1);
  rb_define_singleton_method(m, "escape_html_entities!", escape_html_entities_bang, 1);
  rb_define_singleton_method(m, "escape_js_separators!", escape_js_separators_bang, 1);
}
