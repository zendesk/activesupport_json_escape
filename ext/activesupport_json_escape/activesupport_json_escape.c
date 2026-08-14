#include <ruby.h>
#include <ruby/encoding.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <limits.h>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define ASJE_HAVE_NEON 1
#endif

static const char HEX_DIGITS[] = "0123456789abcdef";
static unsigned char JSON_QUOTED_BYTE_LENGTHS[256];

#ifdef ASJE_HAVE_NEON
static inline long
json_quoted_chunk_extra_neon(const unsigned char *src)
{
  uint8x16_t bytes = vld1q_u8(src);
  uint8x16_t extra = vandq_u8(vcltq_u8(bytes, vdupq_n_u8(0x20)), vdupq_n_u8(5));

  // Create a mask for named control characters
  uint8x16_t named_controls = vorrq_u8(
    vorrq_u8(
      vceqq_u8(bytes, vdupq_n_u8('\b')),
      vceqq_u8(bytes, vdupq_n_u8('\t'))
    ),
    vorrq_u8(
      vorrq_u8(
        vceqq_u8(bytes, vdupq_n_u8('\n')),
        vceqq_u8(bytes, vdupq_n_u8('\f'))
      ),
      vceqq_u8(bytes, vdupq_n_u8('\r'))
    )
  );
  // All control characters were tagged with an expansion of 5 above
  // Correct that for named control characters by subtracting 4
  extra = vsubq_u8(extra, vandq_u8(named_controls, vdupq_n_u8(4)));

  // Handle expansion for quote and backslash characters
  uint8x16_t quoted = vorrq_u8(
    vceqq_u8(bytes, vdupq_n_u8('"')),
    vceqq_u8(bytes, vdupq_n_u8('\\'))
  );
  extra = vaddq_u8(extra, vandq_u8(quoted, vdupq_n_u8(1)));

  // Add all lanes together to get the total expansion for this chunk
  return (long)vaddvq_u8(extra);
}
#endif

static VALUE
quote_json_bytes(VALUE self, VALUE str)
{
  Check_Type(str, T_STRING);

  const char *src = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  long extra = 0;
  long scan = 0;

#ifdef ASJE_HAVE_NEON
  for (; scan <= len - 16; scan += 16) {
    long chunk_extra = json_quoted_chunk_extra_neon((const unsigned char *)src + scan);
    if (extra > LONG_MAX - chunk_extra) {
      rb_raise(rb_eArgError, "input is too large to quote as a JSON byte string");
    }
    extra += chunk_extra;
  }
#endif

  // Iterate over the remaining bytes (or full string if NEON is not available)
  for (; scan < len; scan++) {
    long byte_extra = JSON_QUOTED_BYTE_LENGTHS[(unsigned char)src[scan]] - 1;
    if (extra > LONG_MAX - byte_extra) {
      rb_raise(rb_eArgError, "input is too large to quote as a JSON byte string");
    }
    extra += byte_extra;
  }

  if (len > LONG_MAX - 2 || extra > LONG_MAX - len - 2) {
    rb_raise(rb_eArgError, "input is too large to quote as a JSON byte string");
  }
  long result_len = len + extra + 2;

  VALUE result = rb_str_buf_new(result_len);
  char *dst = RSTRING_PTR(result);

  // Ruby allocation is a GC safepoint. Re-fetch the input pointer defensively.
  src = RSTRING_PTR(str);

  // Simple string fast path
  if (extra == 0) {
    dst[0] = '"';
    if (len > 0) {
      memcpy(dst + 1, src, len);
    }
    dst[len + 1] = '"';
    rb_str_set_len(result, result_len);
    rb_enc_associate(result, rb_ascii8bit_encoding());
    return result;
  }

  long out = 0;
  dst[out++] = '"';
  long i = 0;
  while (i < len) {
    // Skip past bytes that don't need quoting
    long run_start = i;
    while (i < len && JSON_QUOTED_BYTE_LENGTHS[(unsigned char)src[i]] == 1) {
      i++;
    }
    long run_len = i - run_start;
    if (run_len > 0) {
      memcpy(dst + out, src + run_start, run_len);
      out += run_len;
    }
    if (i == len) {
      break;
    }

    unsigned char c = (unsigned char)src[i++];
    switch (c) {
      case '"':
        dst[out++] = '\\';
        dst[out++] = '"';
        break;
      case '\\':
        dst[out++] = '\\';
        dst[out++] = '\\';
        break;
      case '\b':
        dst[out++] = '\\';
        dst[out++] = 'b';
        break;
      case '\f':
        dst[out++] = '\\';
        dst[out++] = 'f';
        break;
      case '\n':
        dst[out++] = '\\';
        dst[out++] = 'n';
        break;
      case '\r':
        dst[out++] = '\\';
        dst[out++] = 'r';
        break;
      case '\t':
        dst[out++] = '\\';
        dst[out++] = 't';
        break;
      default:
        if (c < 0x20) {
          dst[out++] = '\\';
          dst[out++] = 'u';
          dst[out++] = '0';
          dst[out++] = '0';
          dst[out++] = HEX_DIGITS[c >> 4];
          dst[out++] = HEX_DIGITS[c & 0x0f];
        } else {
          dst[out++] = (char)c;
        }
    }
  }
  dst[out++] = '"';

  rb_str_set_len(result, result_len);
  rb_enc_associate(result, rb_ascii8bit_encoding());
  return result;
}

static VALUE
do_escape(VALUE str, bool escape_html, bool escape_js)
{
  StringValue(str);
  rb_check_frozen(str);

  const char *src = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);

  long extra = 0;
  long i = 0;
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
  // Prime the quoted output length map
  for (int i = 0; i < 256; i++) {
    JSON_QUOTED_BYTE_LENGTHS[i] = 1;
  }
  for (int i = 0; i < 0x20; i++) {
    JSON_QUOTED_BYTE_LENGTHS[i] = 6;
  }
  JSON_QUOTED_BYTE_LENGTHS['"'] = 2;
  JSON_QUOTED_BYTE_LENGTHS['\\'] = 2;
  JSON_QUOTED_BYTE_LENGTHS['\b'] = 2;
  JSON_QUOTED_BYTE_LENGTHS['\f'] = 2;
  JSON_QUOTED_BYTE_LENGTHS['\n'] = 2;
  JSON_QUOTED_BYTE_LENGTHS['\r'] = 2;
  JSON_QUOTED_BYTE_LENGTHS['\t'] = 2;

  VALUE m = rb_define_module("ActiveSupportJsonEscape");
  rb_define_singleton_method(m, "escape_full!", escape_full_bang, 1);
  rb_define_singleton_method(m, "escape_html_entities!", escape_html_entities_bang, 1);
  rb_define_singleton_method(m, "escape_js_separators!", escape_js_separators_bang, 1);
  rb_define_singleton_method(m, "quote_json_bytes", quote_json_bytes, 1);
}
