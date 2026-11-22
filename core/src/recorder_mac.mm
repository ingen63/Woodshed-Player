// Recording on macOS: the system audio (macOS 14.2+) through a Core Audio process tap, or the
// microphone (#113, default input device through miniaudio, MicInput in recorder_core.cpp), both
// as FLAC with 24 bit (#118).
// System audio: tap on all processes except Woodshed Player -> private aggregate device -> IOProc
// -> ring buffer -> writer thread -> FLAC. Without the permission macOS delivers only silence
// (wp_rec_only_silence). Ring buffer, writer thread, file and level are platform-independent
// and tested without an audio device (recorder_core.cpp, #68); this file only drives Core Audio.
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>

#include "recorder_core.hpp"
#include "wp_core.h"

namespace {

struct Recorder {
  std::mutex mutex;
  std::string error;
  OSStatus osStatus = noErr; // of the last failed start
  std::atomic<bool> recording{false};
  double sampleRate = 48000; // Takt des Aggregate-Devices (= Ausgabegerät), nicht das Tap-Format
  UInt32 tapChannels = 2;
  bool tapNonInterleaved = false;

  AudioObjectID tap = kAudioObjectUnknown;
  AudioObjectID aggregate = kAudioObjectUnknown;
  AudioDeviceIOProcID ioProc = nullptr;
  dispatch_queue_t queue = nullptr;

  wp::rec::Capture capture; // ring buffer, writer thread, file, level
  wp::rec::MicInput mic;    // #113: only open while recording from the microphone
};

Recorder &rec() {
  static Recorder r;
  return r;
}

// Input buffers handed to the core per callback; the tap buffers are the last ones.
constexpr UInt32 kMaxBuffers = 64;

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

// Audio thread: the input buffer list goes to the core, which takes the tap data from its last
// buffers.
void onInput(Recorder *r, const AudioBufferList *in) {
  if (!in || in->mNumberBuffers == 0)
    return;
  const UInt32 count = std::min(kMaxBuffers, in->mNumberBuffers);
  const UInt32 first = in->mNumberBuffers - count;
  wp::rec::TapBuffer buffers[kMaxBuffers];
  for (UInt32 i = 0; i < count; ++i) {
    const AudioBuffer &b = in->mBuffers[first + i];
    buffers[i] = {b.mNumberChannels, b.mDataByteSize, static_cast<const float *>(b.mData)};
  }
  r->capture.push(buffers, count, {r->tapChannels, r->tapNonInterleaved});
}

void teardownTap(Recorder &r) API_AVAILABLE(macos(14.2)) {
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
}

void teardown(Recorder &r) {
  if (@available(macOS 14.2, *))
    teardownTap(r);
  r.mic.close();
  r.capture.close();
  r.recording.store(false);
}

// #113: the default input device into a FLAC file. Without the microphone permission macOS
// delivers silence; the app asks for the permission before it starts.
int startMic(Recorder &r, const char *path) {
  if (!r.mic.open())
    return fail(r, WP_REC_ERR_NO_INPUT, "No input device could be opened");
  r.sampleRate = r.mic.sampleRate();
  const int opened = r.capture.open(path, r.sampleRate, wp::rec::FileFormat::Flac);
  if (opened == WP_REC_ERR_OUT_OF_MEMORY)
    return fail(r, WP_REC_ERR_OUT_OF_MEMORY, "No memory for the ring buffer");
  if (opened != 0)
    return fail(r, WP_REC_ERR_FILE, "FLAC file could not be created");
  if (!r.mic.start(r.capture))
    return fail(r, WP_REC_ERR_START, "Microphone could not be started");
  return 0;
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

  // 3. Target: ring buffer (2 s), FLAC file (#118) and writer thread.
  const int opened = r.capture.open(path, r.sampleRate, wp::rec::FileFormat::Flac);
  if (opened == WP_REC_ERR_OUT_OF_MEMORY)
    return fail(r, WP_REC_ERR_OUT_OF_MEMORY, "No memory for the ring buffer");
  if (opened != 0)
    return fail(r, WP_REC_ERR_FILE, "FLAC file could not be created");

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

int wp_rec_source_available(int source) {
  if (source == WP_REC_SOURCE_MIC)
    return 1;
  if (source == WP_REC_SOURCE_SYSTEM) {
    if (@available(macOS 14.2, *))
      return 1;
  }
  return 0;
}

// The microphone records on every supported macOS.
int wp_rec_available(void) { return wp_rec_source_available(WP_REC_SOURCE_MIC); }

int wp_rec_start_source(const char *path, int source) {
  auto &r = rec();
  std::lock_guard<std::mutex> lock(r.mutex);
  if (r.recording.load())
    return 0;
  r.error.clear();
  r.osStatus = noErr;
  if (!path)
    return fail(r, WP_REC_ERR_INVALID_PATH, "No file path");
  if (!wp_rec_source_available(source))
    return fail(r, WP_REC_ERR_UNSUPPORTED,
                source == WP_REC_SOURCE_SYSTEM ? "Recording requires macOS 14.2 or later"
                                               : "Unknown recording source");
  r.capture.meter().reset();
  int res = 0;
  if (source == WP_REC_SOURCE_MIC) {
    res = startMic(r, path);
  } else if (@available(macOS 14.2, *)) {
    res = startTap(r, path);
  }
  if (res != 0) {
    teardown(r);
    return res;
  }
  r.recording.store(true);
  return 0;
}

int wp_rec_start(const char *path) { return wp_rec_start_source(path, WP_REC_SOURCE_SYSTEM); }

void wp_rec_stop(void) {
  auto &r = rec();
  std::lock_guard<std::mutex> lock(r.mutex);
  teardown(r);
}

int wp_rec_is_recording(void) { return rec().recording.load() ? 1 : 0; }

double wp_rec_seconds(void) {
  auto &r = rec();
  return static_cast<double>(r.capture.meter().frames()) / r.sampleRate;
}

float wp_rec_level(void) { return rec().capture.meter().takeLevel(); }

int wp_rec_only_silence(void) { return rec().capture.meter().onlySilence() ? 1 : 0; }

int wp_rec_os_status(void) { return static_cast<int>(rec().osStatus); }

const char *wp_rec_error(void) { return rec().error.c_str(); }

} // extern "C"
