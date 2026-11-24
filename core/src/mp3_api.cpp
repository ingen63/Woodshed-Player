// C-API of the MP3 export (#141), see wp_core.h and mp3_export.hpp.
#include "mp3_export.hpp"
#include "wp_core.h"

extern "C" {

int wp_mp3_available(const char *lame_path) {
  return wp::mp3::loadLame(lame_path) != nullptr ? 1 : 0;
}

int wp_mp3_export(const char *lame_path, const char *in_path, const char *out_path, int kbps,
                  int *cancel, double *progress) {
  return wp::mp3::exportFile(lame_path, in_path, out_path, kbps, cancel, progress);
}

} // extern "C"
