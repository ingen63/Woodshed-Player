// MP3 export (#141): decodes an audio file and encodes it as MP3 (CBR, 44.1 kHz, the channels of
// the source, at most two) with LAME. LAME (LGPL) is never linked: it is loaded at run time with
// dlopen from a path the app gives (CLAUDE.md, licences), so the app runs without it and the
// library can be replaced. The MP3 file holds only MPEG frames (the first is LAME's info frame);
// the app writes the ID3 tag in front of it.
#pragma once

#include <memory>
#include <string>

namespace wp::mp3 {

constexpr int kSampleRate = 44100;
constexpr int kMinBitrate = 32;
constexpr int kMaxBitrate = 320;
constexpr int kDefaultBitrate = 192;

// PCM of a decoded file: float, interleaved, `channels` (1 or 2) at `sampleRate`.
class PcmReader {
public:
  virtual ~PcmReader() = default;
  int channels = 0;
  int sampleRate = 0;
  // Frames in the file; 0 if unknown.
  long long frames = 0;
  // Reads up to `count` frames into `out`; returns the frames read, 0 at the end, < 0 on an error.
  virtual long long read(float *out, long long count) = 0;

protected:
  PcmReader() = default;
  PcmReader(const PcmReader &) = default;
  PcmReader &operator=(const PcmReader &) = default;
};

// Opens `path` with miniaudio (MP3, WAV, FLAC), more than two channels are mixed to two. nullptr
// and `code` (kErrFileNotFound, kErrUnsupportedFormat, ...) if it cannot.
std::unique_ptr<PcmReader> openMiniaudio(const char *path, int &code);

// Opens `path` with the system's decoder (Apple: ExtAudioFile, for M4A/AAC); nullptr elsewhere.
std::unique_ptr<PcmReader> openSystem(const char *path, int &code);

// LAME loaded from `path`, once per path; nullptr if it cannot be loaded or lacks a function.
struct Lame;
const Lame *loadLame(const char *path);

// Encodes `in` to the MP3 file `path` at `kbps` (kMinBitrate … kMaxBitrate). `cancel` (may be null)
// is read between blocks: once non-zero, the file is removed and kErrCancelled returned. `progress`
// (may be null) gets 0 … 1. On any error the output file is removed.
int encode(const Lame &lame, PcmReader &in, const char *path, int kbps, const volatile int *cancel,
           volatile double *progress);

// The whole export of one file: loads LAME, opens `inPath` (miniaudio, then the system decoder) and
// encodes it, see encode().
int exportFile(const char *lamePath, const char *inPath, const char *outPath, int kbps,
               const volatile int *cancel, volatile double *progress);

} // namespace wp::mp3
