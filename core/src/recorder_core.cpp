// Platform-independent part of the recording (#68), see recorder_core.hpp.
#include "recorder_core.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

#include "wp_core.h"

namespace wp::rec {

void LevelMeter::reset() {
  frames_.store(0);
  peak_.store(0.0f);
  onlySilence_.store(true);
}

void LevelMeter::add(float blockPeak, uint32_t blockFrames) {
  frames_.fetch_add(blockFrames);
  if (blockPeak > peak_.load())
    peak_.store(blockPeak);
  if (blockPeak > kSilenceThreshold)
    onlySilence_.store(false);
}

FrameRing::~FrameRing() { uninit(); }

bool FrameRing::init(uint32_t capacityFrames) {
  ready_ = ma_pcm_rb_init(ma_format_f32, kChannels, capacityFrames, nullptr, nullptr, &rb_) ==
           MA_SUCCESS;
  return ready_;
}

void FrameRing::uninit() {
  if (ready_)
    ma_pcm_rb_uninit(&rb_);
  ready_ = false;
}

uint32_t FrameRing::write(const float *frames, uint32_t count) {
  uint32_t left = count;
  while (left > 0) {
    ma_uint32 chunk = left;
    void *dst = nullptr;
    if (ma_pcm_rb_acquire_write(&rb_, &chunk, &dst) != MA_SUCCESS || chunk == 0)
      break;
    std::memcpy(dst, frames, static_cast<size_t>(chunk) * kChannels * sizeof(float));
    ma_pcm_rb_commit_write(&rb_, chunk);
    frames += static_cast<size_t>(chunk) * kChannels;
    left -= chunk;
  }
  return count - left;
}

uint32_t FrameRing::capacity() { return ready_ ? ma_pcm_rb_get_subbuffer_size(&rb_) : 0; }

uint32_t FrameRing::availableRead() { return ma_pcm_rb_available_read(&rb_); }

const float *FrameRing::acquireRead(uint32_t &frames) {
  ma_uint32 n = frames;
  void *buf = nullptr;
  if (ma_pcm_rb_acquire_read(&rb_, &n, &buf) != MA_SUCCESS || n == 0) {
    frames = 0;
    return nullptr;
  }
  frames = n;
  return static_cast<const float *>(buf);
}

void FrameRing::commitRead(uint32_t frames) { ma_pcm_rb_commit_read(&rb_, frames); }

WavFile::~WavFile() { close(); }

bool WavFile::open(const char *path, uint32_t sampleRate) {
  close();
  const ma_encoder_config config =
      ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, kChannels, sampleRate);
  open_ = wp_encoder_init_file(path, &config, &encoder_) == MA_SUCCESS;
  return open_;
}

void WavFile::write(const float *frames, uint32_t count) {
  ma_encoder_write_pcm_frames(&encoder_, frames, count, nullptr);
}

void WavFile::close() {
  if (open_)
    ma_encoder_uninit(&encoder_);
  open_ = false;
}

Capture::~Capture() { close(); }

int Capture::open(const char *path, double sampleRate, FileFormat format, const GateConfig *gate) {
  close();
  gated_ = gate != nullptr;
  if (gate && !gate_.init(sampleRate, kChannels, *gate))
    return WP_REC_ERR_INVALID_ARGUMENT;
  if (!ring_.init(static_cast<uint32_t>(sampleRate * kRingSeconds)))
    return WP_REC_ERR_OUT_OF_MEMORY;
  const auto rate = static_cast<uint32_t>(sampleRate);
  const bool opened =
      format == FileFormat::Flac ? flac_.open(path, rate, kChannels) : wav_.open(path, rate);
  if (!opened)
    return WP_REC_ERR_FILE;
  writerRun_.store(true);
  writer_ = std::thread([this] { writerLoop(); });
  return 0;
}

void Capture::close() {
  writerRun_.store(false);
  if (writer_.joinable()) {
    writer_.join();
    // #147: stopped during a pause: the file ends where it was stopped. After the writer, before
    // the file closes.
    if (gated_) {
      FileSink sink(*this);
      gate_.finish(sink);
    }
  }
  wav_.close();
  flac_.close();
  ring_.uninit();
}

void Capture::writeFrames(const float *frames, uint32_t count) {
  if (flac_.isOpen())
    flac_.write(frames, count);
  else
    wav_.write(frames, count);
}

void Capture::writerLoop() {
  FileSink sink(*this);
  while (writerRun_.load() || ring_.availableRead() > 0) {
    uint32_t n = kWriteFrames;
    if (const float *buf = ring_.acquireRead(n)) {
      if (gated_)
        gate_.feed(buf, n, sink);
      else
        writeFrames(buf, n);
      ring_.commitRead(n);
    } else {
      // Waiting for the audio thread; without the pause the writer only spins (same output).
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  }
}

void Capture::push(const TapBuffer *buffers, uint32_t count, const TapFormat &format) {
  if (!buffers || count == 0)
    return;
  const bool interleaved = !format.nonInterleaved;
  const uint32_t tapBuffers = interleaved ? 1 : std::min(format.channels, count);
  const TapBuffer *buf = &buffers[count - tapBuffers];
  const uint32_t srcCh = interleaved ? std::max<uint32_t>(1, buf[0].channels) : tapBuffers;
  const uint32_t total =
      buf[0].bytes / static_cast<uint32_t>(sizeof(float)) / (interleaved ? srcCh : 1);

  float tmp[kBlockFrames * kChannels];
  float peak = 0;
  uint32_t done = 0;
  while (done < total) {
    const uint32_t n = std::min(kBlockFrames, total - done);
    for (uint32_t i = 0; i < n; ++i) {
      for (uint32_t c = 0; c < kChannels; ++c) {
        const uint32_t sc = std::min(c, srcCh - 1);
        const float v = interleaved ? buf[0].data[static_cast<size_t>(done + i) * srcCh + sc]
                                    : buf[sc].data[done + i];
        tmp[i * kChannels + c] = v;
        peak = std::max(peak, std::fabs(v));
      }
    }
    // On overflow frames are dropped instead of blocking the audio thread.
    ring_.write(tmp, n);
    done += n;
  }
  meter_.add(peak, total);
}

int micOpenError(ma_result result) {
  return result == MA_ACCESS_DENIED ? WP_REC_ERR_ACCESS_DENIED : WP_REC_ERR_NO_INPUT;
}

int micStartError(ma_result result) {
  return result == MA_ACCESS_DENIED ? WP_REC_ERR_ACCESS_DENIED : WP_REC_ERR_START;
}

bool hasInputDeviceOn(ma_context *context) {
  ma_device_info *playback = nullptr;
  ma_device_info *capture = nullptr;
  ma_uint32 playbackCount = 0;
  ma_uint32 captureCount = 0;
  return ma_context_get_devices(context, &playback, &playbackCount, &capture, &captureCount) ==
             MA_SUCCESS &&
         captureCount != 0;
}

bool isSystemInput(bool chosen, ma_backend backend) { return chosen || backend != ma_backend_null; }

bool hasInputDevice(const ma_backend *backends, ma_uint32 backendCount) {
  ma_context own;
  if (ma_context_init(backends, backendCount, nullptr, &own) != MA_SUCCESS)
    return false;
  // Without audio hardware miniaudio falls back to its null backend; its silent capture device is
  // no microphone of the system (only when asked for by name, as in the tests).
  const bool found = isSystemInput(backends != nullptr, own.backend) && hasInputDeviceOn(&own);
  ma_context_uninit(&own);
  return found;
}

MicInput::~MicInput() { close(); }

bool MicInput::open(ma_context *context) {
  close();
  ma_device_config config = ma_device_config_init(ma_device_type_capture);
  config.capture.pDeviceID = nullptr; // default input device of the system
  config.capture.format = ma_format_f32;
  config.capture.channels = kChannels;
  config.sampleRate = 0; // the device's own rate, no resampling
  config.dataCallback = onData;
  config.pUserData = this;
  result_ = ma_device_init(context, &config, &device_);
  open_ = result_ == MA_SUCCESS;
  return open_;
}

double MicInput::sampleRate() const { return open_ ? device_.sampleRate : 0.0; }

bool MicInput::start(Capture &capture) {
  if (!open_)
    return false;
  capture_ = &capture;
  result_ = ma_device_start(&device_);
  return result_ == MA_SUCCESS;
}

void MicInput::close() {
  // Stops the device and waits for the last callback; afterwards none reaches the capture.
  if (open_)
    ma_device_uninit(&device_);
  open_ = false;
}

void MicInput::deliver(Capture &capture, const float *input, uint32_t frames) {
  const TapBuffer buffer{kChannels, frames * kChannels * static_cast<uint32_t>(sizeof(float)),
                         input};
  capture.push(&buffer, 1, {kChannels, false});
}

void MicInput::onData(ma_device *device, void * /*output*/, const void *input, ma_uint32 frames) {
  auto *self = static_cast<MicInput *>(device->pUserData);
  if (self->capture_ && input)
    deliver(*self->capture_, static_cast<const float *>(input), frames);
}

SimulatedInput::~SimulatedInput() { close(); }

void SimulatedInput::render(float *out, uint32_t frames, uint64_t position, bool tone) {
  for (uint32_t i = 0; i < frames; ++i) {
    float v = 0.0f;
    if (tone) {
      // The phase from the frame number modulo one second: exact over any length.
      const auto frame = static_cast<double>((position + i) % static_cast<uint64_t>(kSampleRate));
      constexpr double kTwoPi = 6.283185307179586;
      v = kToneAmplitude * static_cast<float>(std::sin(kTwoPi * kToneHz * frame / kSampleRate));
    }
    out[static_cast<size_t>(i) * kChannels] = v;
    out[static_cast<size_t>(i) * kChannels + 1] = v;
  }
}

void SimulatedInput::start(Capture &capture) {
  close();
  run_.store(true);
  thread_ = std::thread([this, &capture] { loop(capture); });
}

void SimulatedInput::close() {
  run_.store(false);
  if (thread_.joinable())
    thread_.join();
}

void SimulatedInput::loop(Capture &capture) {
  using Clock = std::chrono::steady_clock;
  float block[kBlockFrames * kChannels];
  const auto begin = Clock::now();
  uint64_t delivered = 0;
  while (run_.load()) {
    // The sine goes on where the last start left it, so two takes alike in timing still differ
    // (the library keeps only one of two identical files).
    render(block, kBlockFrames, position_, tone_.load());
    MicInput::deliver(capture, block, kBlockFrames);
    position_ += kBlockFrames;
    delivered += kBlockFrames;
    // Real-time pace: the next block is due when the frames so far have played.
    const auto due = std::chrono::duration<double>(static_cast<double>(delivered) / kSampleRate);
    std::this_thread::sleep_until(begin + std::chrono::duration_cast<Clock::duration>(due));
  }
}

bool MicSource::setInput(int input) {
  if (input < WP_REC_INPUT_DEVICE || input > WP_REC_INPUT_NONE)
    return false;
  input_.store(input);
  sim_.setTone(input == WP_REC_INPUT_TONE);
  return true;
}

bool MicSource::available() {
  switch (input_.load()) {
  case WP_REC_INPUT_DEVICE:
    if (device_ < 0)
      device_ = (context_ ? hasInputDeviceOn(context_) : hasInputDevice()) ? 1 : 0;
    return device_ == 1;
  case WP_REC_INPUT_NONE:
    return false;
  default:
    return true;
  }
}

int MicSource::open() {
  close();
  switch (input_.load()) {
  case WP_REC_INPUT_SILENCE:
  case WP_REC_INPUT_TONE:
    simOpen_ = true;
    return 0;
  case WP_REC_INPUT_DENIED:
    return micOpenError(MA_ACCESS_DENIED);
  case WP_REC_INPUT_NONE:
    return micOpenError(MA_NO_DEVICE);
  default:
    return mic_.open(context_) ? 0 : micOpenError(mic_.result());
  }
}

double MicSource::sampleRate() const {
  return simOpen_ ? SimulatedInput::kSampleRate : mic_.sampleRate();
}

int MicSource::start(Capture &capture) {
  if (simOpen_) {
    sim_.start(capture);
    return 0;
  }
  if (mic_.start(capture))
    return 0;
  return micStartError(mic_.result());
}

void MicSource::close() {
  sim_.close();
  simOpen_ = false;
  mic_.close();
}

} // namespace wp::rec
