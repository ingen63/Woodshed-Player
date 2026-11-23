// Trimming the start and end of an audio file (#116). Works on the bytes of a whole file in memory,
// so the native app and the web app (WASM, no file system) cut alike.
//  - WAV (PCM or float): the samples are copied, exact to the sample; other chunks stay.
//  - FLAC: decoded and encoded again with libFLAC (lossless, same bit depth); the tags (Vorbis
//    comment, pictures) stay, the seek table and cue sheet go.
//  - MP3 (MPEG-1/2/2.5 Layer III): cut at frame boundaries without encoding again. Before the
//    first audible frame come an empty frame carrying its bit reservoir and the frame before it
//    (for the overlap of the filter bank), so it decodes as in the old file, without a click. A new
//    Info/Xing frame with a LAME tag (encoder delay and padding) makes decoders that honour it
//    (dr_mp3 in the core does) start and end exactly at the chosen samples; others play up to two
//    frames more at the start. ID3 and APE tags stay.
//  - AAC in ADTS: cut at the nearest frame boundary (1024 samples, about 23 ms at 44.1 kHz).
//  - MP4/M4A with one AAC or ALAC track (#120): cut at the nearest sample boundaries (an AAC frame
//    of 1024 samples, about 23 ms at 44.1 kHz; ALAC 4096) without encoding again. An edit list
//    skips the encoder delay and the AAC frame before the first one (for the filter bank), so the
//    file starts without a click; the tags (with the cover) stay. Several audio tracks:
//    WP_ERR_MULTIPLE_TRACKS, fragmented MP4: WP_ERR_FRAGMENTED.
//  - Everything else: WP_ERR_UNSUPPORTED_FORMAT.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace wp::trim {

enum class Format { Unknown, Wav, Flac, Mp3, Adts, Mp4 };

// Format of the file, after skipping leading ID3v2 tags.
Format detect(const uint8_t *data, size_t size);

// The remaining part must be at least this long (#116/AK7).
constexpr double kMinSeconds = 1.0;

struct Result {
  int code = 0;               // WP_OK or WP_ERR_* (< 0)
  std::vector<uint8_t> bytes; // the trimmed file
  double start = 0;           // where the new file starts in the old one (seconds)
  double end = 0;             // where it ends in the old one (seconds)
};

// Keeps [start, end] seconds of the file. Both are clamped to the length of the file; afterwards at
// least kMinSeconds must remain (WP_ERR_INVALID_ARGUMENT otherwise, also for NaN). The result
// says where the cut really is: it differs from the request by at most half an ADTS frame or MP4
// sample, and an MP3 without LAME tag cut within its first 529 samples starts at sample 529.
// WP_ERR_UNSUPPORTED_FORMAT for unknown or damaged files, WP_ERR_MULTIPLE_TRACKS and
// WP_ERR_FRAGMENTED for MP4 files it cannot cut, WP_ERR_OUT_OF_MEMORY (also for MP4 files from 4
// GiB on, whose new tables would need 64-bit offsets).
Result trim(const uint8_t *data, size_t size, double start, double end);

} // namespace wp::trim
