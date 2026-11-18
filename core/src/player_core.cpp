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

int decodeFile(const std::string& path, int sampleRate, const std::atomic<bool>& cancel,
               std::atomic<double>& progress, Source& out) {
    if (int err = checkReadable(path); err != kOk) return err;

    ma_decoder_config cfg =
        ma_decoder_config_init(ma_format_f32, Player::kChannels, static_cast<ma_uint32>(sampleRate));
    ma_decoder dec;
    if (ma_result r = ma_decoder_init_file(path.c_str(), &cfg, &dec); r != MA_SUCCESS) {
        return r == MA_DOES_NOT_EXIST || r == MA_ACCESS_DENIED ? mapOpenError(r) : kErrUnsupportedFormat;
    }
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
            if (cancel.load()) {
                result = kErrCancelled;
                break;
            }
            ma_uint64 read = 0;
            const ma_result r = ma_decoder_read_pcm_frames(&dec, buf.data(), kBlock, &read);
            out.data.insert(out.data.end(), buf.begin(), buf.begin() + static_cast<long>(read * Player::kChannels));
            frames += static_cast<long long>(read);
            if (total > 0) progress.store(std::min(1.0, static_cast<double>(frames) / static_cast<double>(total)));
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
    }
    return result;
}

}  // namespace

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
        if (result == kOk && !engine_.submitSource(std::move(source))) result = kErrBusy;
    } catch (const std::bad_alloc&) {
        result = kErrOutOfMemory;
    }
    if (result == kOk) loadProgress_.store(1.0);
    loadState_.store(result == kOk ? kLoadReady : result);
}

int Player::waitForLoad() {
    std::lock_guard<std::mutex> lock(loadMutex_);
    if (loader_.joinable()) loader_.join();
    const int s = loadState_.load();
    return s < 0 ? s : kOk;
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
