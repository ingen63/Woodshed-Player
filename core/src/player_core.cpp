#include "player_core.hpp"

#include <algorithm>
#include <new>
#include <vector>

#include "miniaudio_impl.hpp"

namespace wp {

const char* errorMessage(int code) {
    switch (code) {
        case kOk: return "Kein Fehler";
        case kErrInvalidArgument: return "Ungültiger Aufruf";
        case kErrFileNotFound: return "Datei nicht gefunden";
        case kErrUnsupportedFormat: return "Format unbekannt oder Datei beschädigt";
        case kErrDeviceUnavailable: return "Audiogerät nicht verfügbar";
        case kErrOutOfMemory: return "Nicht genug Speicher für diese Datei";
        case kErrFileUnreadable: return "Datei kann nicht gelesen werden";
        case kErrCancelled: return "Laden abgebrochen";
        case kErrBusy: return "Audio-Kern ausgelastet, bitte erneut versuchen";
        default: return "Unbekannter Fehler";
    }
}

bool pausesPlayback(DeviceEvent e) {
    switch (e) {
        case DeviceEvent::Rerouted:
        case DeviceEvent::InterruptionBegan:
        case DeviceEvent::Stopped:
            return true;
        case DeviceEvent::Started:
        case DeviceEvent::InterruptionEnded:
            return false;
    }
    return false;
}

namespace {

int mapOpenError(ma_result r) {
    switch (r) {
        case MA_DOES_NOT_EXIST:
        case MA_INVALID_FILE:  // u. a. leerer Pfad
            return kErrFileNotFound;
        case MA_ACCESS_DENIED:
        case MA_IS_DIRECTORY:
        case MA_IO_ERROR:
        case MA_TOO_MANY_OPEN_FILES:
            return kErrFileUnreadable;
        case MA_OUT_OF_MEMORY:
            return kErrOutOfMemory;
        default:
            return kErrUnsupportedFormat;
    }
}

// Prüft vorab, ob die Datei existiert und lesbar ist; miniaudio meldet sonst nur «kein Decoder».
int checkReadable(const std::string& path) {
    ma_default_vfs vfs;  // Standard-Dateisystem von miniaudio (UTF-8 auch unter Windows)
    if (ma_default_vfs_init(&vfs, nullptr) != MA_SUCCESS) return kErrFileUnreadable;
    ma_vfs_file f = nullptr;
    const ma_result r = ma_vfs_open(&vfs, path.c_str(), MA_OPEN_MODE_READ, &f);
    if (r != MA_SUCCESS) return mapOpenError(r);
    ma_file_info info{};
    const ma_result ri = ma_vfs_info(&vfs, f, &info);
    ma_vfs_close(&vfs, f);
    if (ri == MA_SUCCESS && info.sizeInBytes == 0) return kErrUnsupportedFormat;
    return kOk;
}

// Liest einen geöffneten Decoder vollständig nach `out` (Stereo, f32, Samplerate des Decoders).
int readAll(ma_decoder& dec, const std::atomic<bool>* cancel, std::atomic<double>* progress, Source& out) {
    ma_uint64 total = 0;
    if (ma_decoder_get_length_in_pcm_frames(&dec, &total) != MA_SUCCESS) total = 0;

    int result = kOk;
    try {
        constexpr ma_uint64 kBlock = 8192;
        out.data.clear();
        if (total > 0) out.data.reserve(static_cast<size_t>((total + kBlock) * Player::kChannels));
        std::vector<float> buf(kBlock * Player::kChannels);
        long long frames = 0;
        for (;;) {
            if (cancel && cancel->load()) {
                result = kErrCancelled;
                break;
            }
            ma_uint64 read = 0;
            const ma_result r = ma_decoder_read_pcm_frames(&dec, buf.data(), kBlock, &read);
            out.data.insert(out.data.end(), buf.begin(), buf.begin() + static_cast<long>(read * Player::kChannels));
            frames += static_cast<long long>(read);
            if (progress && total > 0)
                progress->store(std::min(1.0, static_cast<double>(frames) / static_cast<double>(total)));
            if (r != MA_SUCCESS || read == 0) {
                if (r != MA_SUCCESS && r != MA_AT_END && frames == 0) result = kErrUnsupportedFormat;
                break;
            }
        }
        out.frames = frames;
        if (result == kOk && frames == 0) result = kErrUnsupportedFormat;
    } catch (const std::bad_alloc&) {
        result = kErrOutOfMemory;
    }
    ma_decoder_uninit(&dec);
    if (result != kOk) {
        out.data.clear();
        out.data.shrink_to_fit();
        out.frames = 0;
    }
    return result;
}

ma_decoder_config decoderConfig(int sampleRate) {
    return ma_decoder_config_init(ma_format_f32, Player::kChannels, static_cast<ma_uint32>(sampleRate));
}

int decodeFile(const std::string& path, int sampleRate, const std::atomic<bool>& cancel,
               std::atomic<double>& progress, Source& out) {
    if (int err = checkReadable(path); err != kOk) return err;

    ma_decoder_config cfg = decoderConfig(sampleRate);
    ma_decoder dec;
    if (ma_result r = ma_decoder_init_file(path.c_str(), &cfg, &dec); r != MA_SUCCESS) {
        return r == MA_DOES_NOT_EXIST || r == MA_ACCESS_DENIED ? mapOpenError(r) : kErrUnsupportedFormat;
    }
    return readAll(dec, &cancel, &progress, out);
}

}  // namespace

double fileDuration(const std::string& path) {
    if (path.empty()) return kErrInvalidArgument;
    if (int err = checkReadable(path); err != kOk) return err;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);  // ohne Umwandlung
    ma_decoder dec;
    if (ma_result r = ma_decoder_init_file(path.c_str(), &cfg, &dec); r != MA_SUCCESS) {
        return r == MA_DOES_NOT_EXIST || r == MA_ACCESS_DENIED ? mapOpenError(r) : kErrUnsupportedFormat;
    }
    ma_uint64 frames = 0;
    const ma_result r = ma_decoder_get_length_in_pcm_frames(&dec, &frames);
    const double rate = dec.outputSampleRate;
    ma_decoder_uninit(&dec);
    if (r != MA_SUCCESS || frames == 0 || rate <= 0) return kErrUnsupportedFormat;
    return static_cast<double>(frames) / rate;
}

int decodeMemory(const void* data, size_t size, int sampleRate, Source& out) {
    if (!data || sampleRate < 1) return kErrInvalidArgument;
    if (size == 0) return kErrUnsupportedFormat;
    ma_decoder_config cfg = decoderConfig(sampleRate);
    ma_decoder dec;
    if (ma_decoder_init_memory(data, size, &cfg, &dec) != MA_SUCCESS) return kErrUnsupportedFormat;
    return readAll(dec, nullptr, nullptr, out);
}

int convertPcm(const float* interleaved, int channels, long long frames, int srcRate, int dstRate, Source& out) {
    if (!interleaved || channels < 1 || frames < 1 || srcRate < 1 || dstRate < 1) return kErrInvalidArgument;
    ma_data_converter_config cfg =
        ma_data_converter_config_init(ma_format_f32, ma_format_f32, static_cast<ma_uint32>(channels),
                                      Player::kChannels, static_cast<ma_uint32>(srcRate),
                                      static_cast<ma_uint32>(dstRate));
    ma_data_converter conv;
    if (ma_data_converter_init(&cfg, nullptr, &conv) != MA_SUCCESS) return kErrInvalidArgument;
    int result = kOk;
    try {
        ma_uint64 expected = 0;
        if (ma_data_converter_get_expected_output_frame_count(&conv, static_cast<ma_uint64>(frames), &expected) !=
            MA_SUCCESS)
            expected = static_cast<ma_uint64>(frames);
        out.data.clear();
        out.data.reserve(static_cast<size_t>(expected + 16) * Player::kChannels);
        constexpr ma_uint64 kBlock = 8192;
        std::vector<float> buf(kBlock * Player::kChannels);
        ma_uint64 done = 0;  // gelesene Eingabe-Frames
        for (;;) {
            ma_uint64 in = static_cast<ma_uint64>(frames) - done;
            ma_uint64 got = kBlock;
            if (ma_data_converter_process_pcm_frames(&conv, interleaved + done * static_cast<ma_uint64>(channels), &in,
                                                     buf.data(), &got) != MA_SUCCESS) {
                result = kErrUnsupportedFormat;
                break;
            }
            done += in;
            out.data.insert(out.data.end(), buf.begin(), buf.begin() + static_cast<long>(got * Player::kChannels));
            if (got == 0) break;
        }
        out.frames = static_cast<long long>(out.data.size() / Player::kChannels);
        if (result == kOk && out.frames == 0) result = kErrUnsupportedFormat;
    } catch (const std::bad_alloc&) {
        result = kErrOutOfMemory;
    }
    ma_data_converter_uninit(&conv, nullptr);
    if (result != kOk) {
        out.data.clear();
        out.data.shrink_to_fit();
        out.frames = 0;
    }
    return result;
}

Player::Player(int sampleRate) : sampleRate_(std::max(1, sampleRate)) {
    engine_.configure(kChannels, sampleRate_);
    metronome_.setSampleRate(sampleRate_);
}

Player::~Player() {
    std::lock_guard<std::mutex> lock(loadMutex_);
    cancelLoad();
}

void Player::render(float* out, int frames) {
    engine_.render(out, frames);
    metronome_.renderAdd(out, frames, kChannels);
}

void Player::cancelLoad() {
    if (loader_.joinable()) {
        cancel_.store(true);
        loader_.join();
    }
    cancel_.store(false);
}

int Player::loadAsync(const std::string& path) {
    std::lock_guard<std::mutex> lock(loadMutex_);
    cancelLoad();
    engine_.collectGarbage();
    int err = kOk;
    if (path.empty()) err = kErrInvalidArgument;
    else if (!deviceAvailable()) err = kErrDeviceUnavailable;
    if (err != kOk) {
        loadState_.store(err);
        return err;
    }
    loadProgress_.store(0.0);
    loadState_.store(kLoadRunning);
    try {
        loader_ = std::thread(&Player::runLoad, this, path);
    } catch (const std::exception&) {
        loadState_.store(kErrOutOfMemory);
        return kErrOutOfMemory;
    }
    return kOk;
}

void Player::runLoad(std::string path) {
    int result = kOk;
    try {
        auto source = std::make_unique<Source>();
        result = decodeFile(path, sampleRate_, cancel_, loadProgress_, *source);
        if (result == kOk) result = setSource(std::move(source));
    } catch (const std::bad_alloc&) {
        result = kErrOutOfMemory;
    }
    if (result == kOk) loadProgress_.store(1.0);
    loadState_.store(result == kOk ? kLoadReady : result);
}

int Player::setSource(std::unique_ptr<Source> source) {
    if (!source || source->frames < 1 ||
        source->data.size() != static_cast<size_t>(source->frames) * static_cast<size_t>(kChannels))
        return kErrInvalidArgument;
    try {
        // Übersicht einmal hier ausserhalb des Audio-Threads berechnen (#28)
        auto peaks = std::make_shared<const Peaks>(source->data.data(), source->frames, kChannels, sampleRate_);
        if (!engine_.submitSource(std::move(source))) return kErrBusy;
        std::lock_guard<std::mutex> lock(peaksMutex_);
        peaks_ = std::move(peaks);
    } catch (const std::bad_alloc&) {
        return kErrOutOfMemory;
    }
    return kOk;
}

int Player::waitForLoad() {
    std::lock_guard<std::mutex> lock(loadMutex_);
    if (loader_.joinable()) loader_.join();
    const int s = loadState_.load();
    return s < 0 ? s : kOk;
}

int Player::waveform(double start, double end, int count, float* mins, float* maxs) const {
    std::shared_ptr<const Peaks> peaks;
    {
        std::lock_guard<std::mutex> lock(peaksMutex_);
        peaks = peaks_;
    }
    return peaks && peaks->query(start, end, count, mins, maxs) ? kOk : kErrInvalidArgument;
}

int Player::load(const std::string& path) {
    const int r = loadAsync(path);
    return r != kOk ? r : waitForLoad();
}

void Player::onDeviceEvent(DeviceEvent e) {
    if (e == DeviceEvent::Started) setDeviceAvailable(true);
    if (!pausesPlayback(e)) return;
    engine_.pause();
    metronome_.stop();
}

}  // namespace wp
