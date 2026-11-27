// miniaudio-Implementierung (eine Übersetzungseinheit). Auf iOS als Objective-C übersetzen
// (miniaudio_impl.m), damit miniaudio die AVAudioSession einrichten kann.
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_GENERATION
#include "miniaudio.h"

#include "miniaudio_impl.hpp"

#ifdef _WIN32
// The UTF-16 form of the UTF-8 path [path] (free with ma_free), or NULL if it is no valid UTF-8.
static wchar_t *wp_wide(const char *path) {
  if (path == NULL)
    return NULL;
  const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
  if (n <= 0)
    return NULL;
  wchar_t *wide = (wchar_t *)ma_malloc((size_t)n * sizeof(wchar_t), NULL);
  if (wide != NULL)
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, n);
  return wide;
}
#endif

ma_result wp_decoder_init_file(const char *path, const ma_decoder_config *config,
                               ma_decoder *decoder) {
#ifdef _WIN32
  wchar_t *wide = wp_wide(path);
  if (wide != NULL) {
    const ma_result result = ma_decoder_init_file_w(wide, config, decoder);
    ma_free(wide, NULL);
    return result;
  }
#endif
  return ma_decoder_init_file(path, config, decoder);
}

ma_result wp_vfs_open(ma_vfs *vfs, const char *path, ma_uint32 mode, ma_vfs_file *file) {
#ifdef _WIN32
  wchar_t *wide = wp_wide(path);
  if (wide != NULL) {
    const ma_result result = ma_vfs_open_w(vfs, wide, mode, file);
    ma_free(wide, NULL);
    return result;
  }
#endif
  return ma_vfs_open(vfs, path, mode, file);
}

ma_result wp_vfs_open_and_read_file(ma_vfs *vfs, const char *path, void **data, size_t *size) {
#ifdef _WIN32
  wchar_t *wide = wp_wide(path);
  if (wide != NULL) {
    const ma_result result = ma_vfs_open_and_read_file_w(vfs, wide, data, size, NULL);
    ma_free(wide, NULL);
    return result;
  }
#endif
  return ma_vfs_open_and_read_file(vfs, path, data, size, NULL);
}
