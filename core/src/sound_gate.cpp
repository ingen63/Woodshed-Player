// Armed recording (#140), see sound_gate.hpp.
#include "sound_gate.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace wp::rec {

float SoundGate::linear(double db) { return static_cast<float>(std::pow(10.0, db / 20.0)); }

bool SoundGate::init(double sampleRate, uint32_t channels, const GateConfig &config) {
  if (!(sampleRate > 0) || channels == 0 || !config.valid())
    return false;
  channels_ = channels;
  threshold_ = linear(config.thresholdDb);
  preroll_ = std::llround(kPrerollSeconds * sampleRate);
  postroll_ = std::llround(config.postrollSeconds * sampleRate);
  silence_ = std::max(postroll_, std::llround(config.silenceSeconds * sampleRate));
  pre_.assign(static_cast<size_t>(preroll_) * channels_, 0.0f);
  pending_.assign(static_cast<size_t>(silence_ - postroll_) * channels_, 0.0f);
  state_.store(GateState::Armed);
  kept_.store(0);
  pos_ = 0;
  first_ = -1;
  last_ = -1;
  preCount_ = 0;
  pendingFrames_ = 0;
  return true;
}

bool SoundGate::loud(const float *frame) const {
  for (uint32_t c = 0; c < channels_; ++c)
    if (std::fabs(frame[c]) > threshold_)
      return true;
  return false;
}

void SoundGate::emit(const float *frames, uint32_t count, FrameSink &sink) {
  if (count == 0)
    return;
  sink.write(frames, count);
  kept_.fetch_add(count);
}

// The lead-in: the ring's frames from oldest to newest (fewer than a second if the stream was
// shorter).
void SoundGate::startRecording(FrameSink &sink) {
  const long long have = std::min(preCount_, preroll_);
  const long long oldest = (preCount_ - have) % std::max<long long>(1, preroll_);
  const long long tail = std::min(have, preroll_ - oldest);
  emit(&pre_[static_cast<size_t>(oldest) * channels_], static_cast<uint32_t>(tail), sink);
  emit(pre_.data(), static_cast<uint32_t>(have - tail), sink);
  state_.store(GateState::Recording);
}

void SoundGate::feed(const float *frames, uint32_t count, FrameSink &sink) {
  uint32_t i = 0;
  while (i < count && state_.load() == GateState::Armed) {
    const float *frame = frames + static_cast<size_t>(i) * channels_;
    if (loud(frame)) {
      first_ = pos_;
      startRecording(sink);
      break;
    }
    if (preroll_ > 0) {
      const auto slot = static_cast<size_t>(preCount_ % preroll_) * channels_;
      std::copy(frame, frame + channels_, &pre_[slot]);
    }
    ++preCount_;
    ++pos_;
    ++i;
  }
  if (i < count && state_.load() == GateState::Recording)
    feedRecording(frames + static_cast<size_t>(i) * channels_, count - i, sink);
}

void SoundGate::feedRecording(const float *frames, uint32_t count, FrameSink &sink) {
  uint32_t run = 0; // start of the frames in this block that go straight to the sink
  uint32_t i = 0;
  for (; i < count; ++i, ++pos_) {
    const float *frame = frames + static_cast<size_t>(i) * channels_;
    if (loud(frame)) {
      last_ = pos_;
      if (pendingFrames_ > 0) {
        // A pause shorter than the limit: the held silence belongs to the recording.
        emit(pending_.data(), static_cast<uint32_t>(pendingFrames_), sink);
        pendingFrames_ = 0;
        run = i;
      }
      continue;
    }
    const long long quiet = pos_ - last_;
    if (quiet <= postroll_)
      continue; // within the tail: written with the run
    if (quiet >= silence_) {
      // The pause is long enough: the recording ends with the tail, the held silence is dropped.
      emit(frames + static_cast<size_t>(run) * channels_, i - run, sink);
      pendingFrames_ = 0;
      state_.store(GateState::Done);
      pos_ += count - i;
      return;
    }
    if (pendingFrames_ == 0) {
      emit(frames + static_cast<size_t>(run) * channels_, i - run, sink);
    }
    std::copy(frame, frame + channels_, &pending_[static_cast<size_t>(pendingFrames_) * channels_]);
    ++pendingFrames_;
    run = i + 1;
  }
  if (pendingFrames_ == 0)
    emit(frames + static_cast<size_t>(run) * channels_, count - run, sink);
}

void SoundGate::finish(FrameSink &sink) {
  if (state_.load() != GateState::Recording || pendingFrames_ == 0)
    return;
  emit(pending_.data(), static_cast<uint32_t>(pendingFrames_), sink);
  pendingFrames_ = 0;
}

} // namespace wp::rec
