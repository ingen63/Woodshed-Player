// C API of trimming (#116), see wp_core.h. Compiled into the native core and the web core alike.
#include "trim.hpp"
#include "wp_core.h"

#include <new>
#include <utility>

struct wp_trim_result {
  wp::trim::Result r;
};

int wp_trim(const void *data, size_t size, double start, double end, wp_trim_result **out) {
  if (!out)
    return WP_ERR_INVALID_ARGUMENT;
  *out = nullptr;
  if (!data)
    return WP_ERR_INVALID_ARGUMENT;
  wp::trim::Result r = wp::trim::trim(static_cast<const uint8_t *>(data), size, start, end);
  if (r.code != WP_OK)
    return r.code;
  auto *result = new (std::nothrow) wp_trim_result{std::move(r)};
  if (!result)
    return WP_ERR_OUT_OF_MEMORY;
  *out = result;
  return WP_OK;
}

const void *wp_trim_data(const wp_trim_result *r) { return r ? r->r.bytes.data() : nullptr; }
size_t wp_trim_size(const wp_trim_result *r) { return r ? r->r.bytes.size() : 0; }
double wp_trim_start(const wp_trim_result *r) { return r ? r->r.start : 0.0; }
double wp_trim_end(const wp_trim_result *r) { return r ? r->r.end : 0.0; }
void wp_trim_free(wp_trim_result *r) { delete r; }
