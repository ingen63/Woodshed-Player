// Aufnahme des Systemtons auf macOS 14.2+ über einen Core Audio Process Tap (ohne Mikrofon).
// Ablauf: Tap auf alle Prozesse ausser Woodshed Player -> private Aggregate-Device -> IOProc ->
// Ringpuffer
// -> Schreib-Thread -> WAV (float32). Ohne Berechtigung liefert macOS nur Stille
// (wp_rec_only_silence).
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#include <unistd.h>

#include <atomic>
#include <cmath>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "miniaudio_impl.hpp"
#include "wp_core.h"

namespace {

struct Recorder {
  std::mutex mutex;
  std::string error;
  OSStatus osStatus = noErr; // of the last failed start
  std::atomic<bool> recording{false};
  std::atomic<bool> onlySilence{true};
  std::atomic<float> peak{0.0f};
  std::atomic<long long> frames{0};
  double sampleRate = 48000; // Takt des Aggregate-Devices (= Ausgabegerät), nicht das Tap-Format
  UInt32 tapChannels = 2;
  bool tapNonInterleaved = false;

  AudioObjectID tap = kAudioObjectUnknown;
  AudioObjectID aggregate = kAudioObjectUnknown;
  AudioDeviceIOProcID ioProc = nullptr;
  dispatch_queue_t queue = nullptr;

  ma_pcm_rb ring{};
  bool ringReady = false;
  ma_encoder encoder{};
  bool encoderReady = false;
  std::thread writer;
  std::atomic<bool> writerRun{false};
};

Recorder &rec() {
  static Recorder r;
  return r;
}

constexpr int kChannels = 2;

template <typename T>
OSStatus getProperty(AudioObjectID obj, AudioObjectPropertySelector sel, T &value,
                     UInt32 qualifierSize = 0, const void *qualifier = nullptr) {
  AudioObjectPropertyAddress addr{sel, kAudioObjectPropertyScopeGlobal,
                                  kAudioObjectPropertyElementMain};
  UInt32 size = sizeof(T);
  return AudioObjectGetPropertyData(obj, &addr, qualifierSize, qualifier, &size,
                                    static_cast<void *>(&value));
}

// Stores the English log text and the OSStatus of a failed start and returns the error code.
int fail(Recorder &r, int code, const char *what, OSStatus st = noErr) {
  r.error = what;
  r.osStatus = st;
  if (st != noErr)
    r.error += " (OSStatus " + std::to_string(st) + ")";
  return code;
}

void writerLoop(Recorder *r) {
  while (r->writerRun.load() || ma_pcm_rb_available_read(&r->ring) > 0) {
    ma_uint32 n = 4096;
    void *buf = nullptr;
    if (ma_pcm_rb_acquire_read(&r->ring, &n, &buf) == MA_SUCCESS && n > 0) {
      ma_encoder_write_pcm_frames(&r->encoder, buf, n, nullptr);
      ma_pcm_rb_commit_read(&r->ring, n);
    } else {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  }
}

// Audio-Thread: Daten aus dem Tap (interleaved oder je Kanal ein Puffer) in den Ringpuffer.
void onInput(Recorder *r, const AudioBufferList *in) {
  if (!in || in->mNumberBuffers == 0)
    return;
  float tmp[1024 * kChannels];
  // Hat das Ausgabegerät eigene Eingänge (z. B. ein Audio-Interface), liefert das Aggregate-Device
  // deren Puffer zuerst; die Tap-Daten stehen in den letzten Puffern.
  const bool interleaved = !r->tapNonInterleaved;
  const UInt32 tapBuffers = interleaved ? 1 : std::min<UInt32>(r->tapChannels, in->mNumberBuffers);
  const UInt32 first = in->mNumberBuffers - tapBuffers;
  const AudioBuffer *buf = &in->mBuffers[first];
  const UInt32 srcCh = interleaved ? std::max<UInt32>(1, buf[0].mNumberChannels) : tapBuffers;
  const UInt32 total = buf[0].mDataByteSize / sizeof(float) / (interleaved ? srcCh : 1);

  float peak = 0;
  UInt32 done = 0;
  while (done < total) {
    const UInt32 n = std::min<UInt32>(1024, total - done);
    for (UInt32 i = 0; i < n; ++i) {
      for (int c = 0; c < kChannels; ++c) {
        const UInt32 sc = std::min<UInt32>(c, srcCh - 1);
        const float *src = interleaved
                               ? static_cast<const float *>(buf[0].mData) + (done + i) * srcCh + sc
                               : static_cast<const float *>(buf[sc].mData) + done + i;
        tmp[i * kChannels + c] = *src;
        peak = std::max(peak, std::fabs(*src));
      }
    }
    // In den Ringpuffer schreiben (bei Überlauf gehen Frames verloren statt zu blockieren).
    ma_uint32 left = n;
    const float *p = tmp;
    while (left > 0) {
      ma_uint32 chunk = left;
      void *dst = nullptr;
      if (ma_pcm_rb_acquire_write(&r->ring, &chunk, &dst) != MA_SUCCESS || chunk == 0)
        break;
      std::memcpy(dst, p, chunk * kChannels * sizeof(float));
      ma_pcm_rb_commit_write(&r->ring, chunk);
      p += chunk * kChannels;
      left -= chunk;
    }
    done += n;
  }
  r->frames.fetch_add(total);
  if (peak > r->peak.load())
    r->peak.store(peak);
  if (peak > 1e-4f)
    r->onlySilence.store(false);
}

void teardown(Recorder &r) API_AVAILABLE(macos(14.2)) {
  if (r.aggregate != kAudioObjectUnknown && r.ioProc) {
    AudioDeviceStop(r.aggregate, r.ioProc);
    AudioDeviceDestroyIOProcID(r.aggregate, r.ioProc);
  }
  r.ioProc = nullptr;
  if (r.aggregate != kAudioObjectUnknown)
    AudioHardwareDestroyAggregateDevice(r.aggregate);
  r.aggregate = kAudioObjectUnknown;
  if (r.tap != kAudioObjectUnknown)
    AudioHardwareDestroyProcessTap(r.tap);
  r.tap = kAudioObjectUnknown;

  r.writerRun.store(false);
  if (r.writer.joinable())
    r.writer.join();
  if (r.encoderReady)
    ma_encoder_uninit(&r.encoder);
  r.encoderReady = false;
  if (r.ringReady)
    ma_pcm_rb_uninit(&r.ring);
  r.ringReady = false;
  r.recording.store(false);
}

int startTap(Recorder &r, const char *path) API_AVAILABLE(macos(14.2)) {
  // 1. Eigenen Prozess ausnehmen, damit die eigene Wiedergabe nicht doppelt im Mitschnitt landet.
  NSMutableArray<NSNumber *> *exclude = [NSMutableArray array];
  pid_t pid = getpid();
  AudioObjectID self = kAudioObjectUnknown;
  if (getProperty(kAudioObjectSystemObject, kAudioHardwarePropertyTranslatePIDToProcessObject, self,
                  sizeof(pid), &pid) == noErr &&
      self != kAudioObjectUnknown) {
    [exclude addObject:@(self)];
  }

  CATapDescription *desc =
      [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:exclude];
  desc.name = @"Woodshed Player Recording";
  desc.privateTap = YES;
  desc.muteBehavior = CATapUnmuted;

  OSStatus st = AudioHardwareCreateProcessTap(desc, &r.tap);
  if (st != noErr)
    return fail(r, WP_REC_ERR_TAP, "System audio tap could not be created", st);

  AudioStreamBasicDescription fmt{};
  st = getProperty(r.tap, kAudioTapPropertyFormat, fmt);
  if (st != noErr) {
    return fail(r, WP_REC_ERR_TAP_FORMAT, "Tap format unknown", st);
  }
  if (!(fmt.mFormatFlags & kAudioFormatFlagIsFloat) || fmt.mBitsPerChannel != 32) {
    return fail(r, WP_REC_ERR_TAP_FORMAT, "Unexpected tap format (not float32)");
  }
  r.sampleRate = fmt.mSampleRate;
  r.tapChannels = std::max<UInt32>(1, fmt.mChannelsPerFrame);
  r.tapNonInterleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;

  // 2. Privates Aggregate-Device mit dem Tap, am Standard-Ausgabegerät ausgerichtet.
  AudioObjectID output = kAudioObjectUnknown;
  CFStringRef outputUID = nullptr;
  if (getProperty(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultSystemOutputDevice,
                  output) != noErr ||
      getProperty(output, kAudioDevicePropertyDeviceUID, outputUID) != noErr || !outputUID) {
    return fail(r, WP_REC_ERR_NO_OUTPUT, "No output device found");
  }
  NSString *outUID = (__bridge_transfer NSString *)outputUID;
  NSDictionary *agg = @{
    @kAudioAggregateDeviceNameKey : @"Woodshed Player Recording",
    @kAudioAggregateDeviceUIDKey : [NSUUID UUID].UUIDString,
    @kAudioAggregateDeviceMainSubDeviceKey : outUID,
    @kAudioAggregateDeviceIsPrivateKey : @YES,
    @kAudioAggregateDeviceIsStackedKey : @NO,
    @kAudioAggregateDeviceTapAutoStartKey : @YES,
    @kAudioAggregateDeviceSubDeviceListKey : @[
      @{@kAudioSubDeviceUIDKey : outUID}
    ],
    @kAudioAggregateDeviceTapListKey : @[
      @{@kAudioSubTapDriftCompensationKey : @YES,
        @kAudioSubTapUIDKey : desc.UUID.UUIDString}
    ],
  };
  st = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)agg, &r.aggregate);
  if (st != noErr) {
    return fail(r, WP_REC_ERR_AGGREGATE, "Aggregate device could not be created", st);
  }
  // Die Daten kommen im Takt des Aggregate-Devices (Ausgabegerät, z. B. 44,1 kHz), auch wenn das
  // Tap-Format eine andere Rate meldet. Mit der Tap-Rate wäre der Mitschnitt zu schnell und zu
  // hoch.
  Float64 deviceRate = 0;
  if (getProperty(r.aggregate, kAudioDevicePropertyNominalSampleRate, deviceRate) == noErr &&
      deviceRate > 0) {
    r.sampleRate = deviceRate;
  }

  // 3. Ziel: Ringpuffer (2 s) und WAV-Datei.
  if (ma_pcm_rb_init(ma_format_f32, kChannels, static_cast<ma_uint32>(r.sampleRate * 2), nullptr,
                     nullptr, &r.ring) != MA_SUCCESS) {
    return fail(r, WP_REC_ERR_OUT_OF_MEMORY, "No memory for the ring buffer");
  }
  r.ringReady = true;
  ma_encoder_config ec = ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, kChannels,
                                                static_cast<ma_uint32>(r.sampleRate));
  if (ma_encoder_init_file(path, &ec, &r.encoder) != MA_SUCCESS) {
    return fail(r, WP_REC_ERR_FILE, "WAV file could not be created");
  }
  r.encoderReady = true;
  r.writerRun.store(true);
  r.writer = std::thread(writerLoop, &r);

  // 4. Starten. Beim ersten Mal fragt macOS hier nach der Berechtigung für Systemaudio.
  if (!r.queue)
    r.queue = dispatch_queue_create("woodshed.recorder", DISPATCH_QUEUE_SERIAL);
  Recorder *rp = &r;
  st = AudioDeviceCreateIOProcIDWithBlock(&r.ioProc, r.aggregate, r.queue,
                                          ^(const AudioTimeStamp *, const AudioBufferList *in,
                                            const AudioTimeStamp *, AudioBufferList *,
                                            const AudioTimeStamp *) {
                                            onInput(rp, in);
                                          });
  if (st != noErr)
    return fail(r, WP_REC_ERR_IO_PROC, "IOProc could not be created", st);
  st = AudioDeviceStart(r.aggregate, r.ioProc);
  if (st != noErr) {
    return fail(r, WP_REC_ERR_START, "Recording could not be started", st);
  }
  return 0;
}

} // namespace

extern "C" {

int wp_rec_available(void) {
  if (@available(macOS 14.2, *))
    return 1;
  return 0;
}

int wp_rec_start(const char *wav_path) {
  auto &r = rec();
  std::lock_guard<std::mutex> lock(r.mutex);
  if (r.recording.load())
    return 0;
  r.error.clear();
  r.osStatus = noErr;
  if (!wav_path)
    return fail(r, WP_REC_ERR_INVALID_PATH, "No file path");
  if (@available(macOS 14.2, *)) {
    r.frames.store(0);
    r.peak.store(0);
    r.onlySilence.store(true);
    int res = startTap(r, wav_path);
    if (res != 0) {
      teardown(r);
      return res;
    }
    r.recording.store(true);
    return 0;
  }
  return fail(r, WP_REC_ERR_UNSUPPORTED, "Recording requires macOS 14.2 or later");
}

void wp_rec_stop(void) {
  auto &r = rec();
  std::lock_guard<std::mutex> lock(r.mutex);
  if (@available(macOS 14.2, *))
    teardown(r);
}

int wp_rec_is_recording(void) { return rec().recording.load() ? 1 : 0; }

double wp_rec_seconds(void) {
  auto &r = rec();
  return static_cast<double>(r.frames.load()) / r.sampleRate;
}

float wp_rec_level(void) { return rec().peak.exchange(0.0f); }

int wp_rec_only_silence(void) { return rec().onlySilence.load() ? 1 : 0; }

int wp_rec_os_status(void) { return static_cast<int>(rec().osStatus); }

const char *wp_rec_error(void) { return rec().error.c_str(); }

} // extern "C"
