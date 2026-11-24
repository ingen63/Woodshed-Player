// MP3 export (#141): no system decoder outside Apple devices; miniaudio reads MP3, WAV and FLAC.
#include "mp3_export.hpp"

#include "player_core.hpp"

namespace wp::mp3 {

std::unique_ptr<PcmReader> openSystem(const char * /*path*/, int &code) {
  code = kErrUnsupportedFormat;
  return nullptr;
}

} // namespace wp::mp3
