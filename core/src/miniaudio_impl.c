// miniaudio-Implementierung (eine Übersetzungseinheit). Auf iOS als Objective-C übersetzen
// (miniaudio_impl.m), damit miniaudio die AVAudioSession einrichten kann.
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_GENERATION
#include "miniaudio.h"

#include "miniaudio_impl.hpp"

ma_result wp_decoder_init_file(const char *path, const ma_decoder_config *config,
                               ma_decoder *decoder) {
#ifdef _WIN32
  if (path != NULL) {
    const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (n > 0) {
      wchar_t *wide = (wchar_t *)ma_malloc((size_t)n * sizeof(wchar_t), NULL);
      if (wide == NULL)
        return MA_OUT_OF_MEMORY;
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, n);
      const ma_result result = ma_decoder_init_file_w(wide, config, decoder);
      ma_free(wide, NULL);
      return result;
    }
  }
#endif
  return ma_decoder_init_file(path, config, decoder);
}
