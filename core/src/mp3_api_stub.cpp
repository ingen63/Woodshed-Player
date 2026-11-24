// MP3 export (#141) in the offline and browser cores: there is no export there; the encoder is
// never available and nothing is written. The C API stays the same as in wp_core.h.
#include "wp_core.h"

extern "C" {

int wp_mp3_available(const char * /*lame_path*/) { return 0; }

int wp_mp3_export(const char * /*lame_path*/, const char * /*in_path*/, const char * /*out_path*/,
                  int /*kbps*/, int * /*cancel*/, double * /*progress*/) {
  return WP_ERR_ENCODER_UNAVAILABLE;
}

} // extern "C"
