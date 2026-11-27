// Einheitliche miniaudio-Einbindung. Die Implementierung steht in miniaudio_impl.c (bzw. .m auf
// iOS).
#pragma once
#define MA_NO_GENERATION
#include "miniaudio.h"

#ifdef __cplusplus
extern "C" {
#endif
// #60/AK4: opens the file at the UTF-8 path `path`. On Windows a narrow path means the ANSI code
// page, so umlauts and other non-ASCII names would not open; there the path goes in as UTF-16.
ma_result wp_decoder_init_file(const char *path, const ma_decoder_config *config,
                               ma_decoder *decoder);
// The same for opening a file of the default file system and for reading it whole.
ma_result wp_vfs_open(ma_vfs *vfs, const char *path, ma_uint32 mode, ma_vfs_file *file);
ma_result wp_vfs_open_and_read_file(ma_vfs *vfs, const char *path, void **data, size_t *size);
#ifdef __cplusplus
}
#endif
