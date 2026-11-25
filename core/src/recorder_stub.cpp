// Aufnahme auf Plattformen ohne Umsetzung (iOS, Android; Windows/Linux folgen in Phase 7).
#include "wp_core.h"

extern "C" {
int wp_rec_available(void) { return 0; }
int wp_rec_source_available(int) { return 0; }
int wp_rec_start(const char *) { return WP_REC_ERR_UNSUPPORTED; }
int wp_rec_start_source(const char *, int) { return WP_REC_ERR_UNSUPPORTED; }
int wp_rec_start_armed(const char *, int, double, double) { return WP_REC_ERR_UNSUPPORTED; }
int wp_rec_start_armed_tail(const char *, int, double, double, double) {
  return WP_REC_ERR_UNSUPPORTED;
}
int wp_rec_gate_state(void) { return WP_REC_GATE_OFF; }
double wp_rec_kept_seconds(void) { return 0.0; }
void wp_rec_stop(void) {}
int wp_rec_is_recording(void) { return 0; }
double wp_rec_seconds(void) { return 0.0; }
float wp_rec_level(void) { return 0.0f; }
int wp_rec_only_silence(void) { return 1; }
int wp_rec_os_status(void) { return 0; }
const char *wp_rec_error(void) { return "Recording is not available on this platform"; }
}
