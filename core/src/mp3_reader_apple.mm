// MP3 export (#141): the system's decoder on Apple devices (ExtAudioFile), for what miniaudio
// cannot read, above all M4A/AAC. See mp3_export.hpp.
#include "mp3_export.hpp"

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#include "player_core.hpp"
#include "sample_rate.hpp"

namespace wp::mp3 {

namespace {

class SystemReader final : public PcmReader {
public:
  ExtAudioFileRef file = nullptr;
  ~SystemReader() override {
    if (file)
      ExtAudioFileDispose(file);
  }
  SystemReader() = default;
  SystemReader(const SystemReader &) = delete;
  SystemReader &operator=(const SystemReader &) = delete;

  long long read(float *out, long long count) override {
    AudioBufferList list;
    list.mNumberBuffers = 1;
    list.mBuffers[0].mNumberChannels = static_cast<UInt32>(channels);
    list.mBuffers[0].mDataByteSize =
        static_cast<UInt32>(count * channels * static_cast<long long>(sizeof(float)));
    list.mBuffers[0].mData = out;
    auto frames = static_cast<UInt32>(count);
    if (ExtAudioFileRead(file, &frames, &list) != noErr)
      return kErrUnsupportedFormat;
    return frames;
  }
};

} // namespace

std::unique_ptr<PcmReader> openSystem(const char *path, int &code) {
  if (!path) {
    code = kErrInvalidArgument;
    return nullptr;
  }
  auto r = std::make_unique<SystemReader>();
  @autoreleasepool {
    NSString *name = [NSString stringWithUTF8String:path]; // nil for invalid UTF-8
    NSURL *url = name ? [NSURL fileURLWithPath:name] : nil;
    if (!url || ExtAudioFileOpenURL((__bridge CFURLRef)url, &r->file) != noErr) {
      code = kErrUnsupportedFormat;
      return nullptr;
    }
  }
  AudioStreamBasicDescription source{};
  UInt32 size = sizeof source;
  if (ExtAudioFileGetProperty(r->file, kExtAudioFileProperty_FileDataFormat, &size, &source) !=
          noErr ||
      source.mChannelsPerFrame < 1) {
    code = kErrUnsupportedFormat;
    return nullptr;
  }
  r->channels = source.mChannelsPerFrame > 1 ? 2 : 1;
  r->sampleRate = static_cast<int>(source.mSampleRate);
  if (!sampleRateSupported(r->sampleRate)) {
    code = kErrUnsupportedSampleRate;
    return nullptr;
  }
  AudioStreamBasicDescription client{};
  client.mSampleRate = source.mSampleRate;
  client.mFormatID = kAudioFormatLinearPCM;
  client.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  client.mChannelsPerFrame = static_cast<UInt32>(r->channels);
  client.mBitsPerChannel = 32;
  client.mFramesPerPacket = 1;
  client.mBytesPerFrame = client.mChannelsPerFrame * sizeof(float);
  client.mBytesPerPacket = client.mBytesPerFrame;
  if (ExtAudioFileSetProperty(r->file, kExtAudioFileProperty_ClientDataFormat, sizeof client,
                              &client) != noErr) {
    code = kErrUnsupportedFormat;
    return nullptr;
  }
  SInt64 length = 0;
  size = sizeof length;
  if (ExtAudioFileGetProperty(r->file, kExtAudioFileProperty_FileLengthFrames, &size, &length) ==
      noErr)
    r->frames = length;
  code = kOk;
  return r;
}

} // namespace wp::mp3
