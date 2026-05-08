#include <ruby.h>
#include <ruby/encoding.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

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
  VALUE m = rb_define_module("ActiveSupportJsonEscape");
  rb_define_singleton_method(m, "escape_full!", escape_full_bang, 1);
  rb_define_singleton_method(m, "escape_html_entities!", escape_html_entities_bang, 1);
  rb_define_singleton_method(m, "escape_js_separators!", escape_js_separators_bang, 1);
}
