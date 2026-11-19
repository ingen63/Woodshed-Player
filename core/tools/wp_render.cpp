// Rendert eine Audiodatei offline mit dem Audio-Kern in eine WAV-Datei (für den Hörvergleich).
// Aufruf: wp_render <eingabe> <ausgabe.wav> <tempo> [sekunden ab Anfang]
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "engine.hpp"
#include "miniaudio_impl.hpp"

int main(int argc, char** argv) {
    if (argc < 4) {
        std::fprintf(stderr, "Usage: %s <input> <output.wav> <tempo> [seconds]\n", argv[0]);
        return 2;
    }
    const double rate = std::atof(argv[3]);
    const double seconds = argc > 4 ? std::atof(argv[4]) : 0;

    ma_decoder_config dc = ma_decoder_config_init(ma_format_f32, 2, 0);
    ma_decoder dec;
    if (ma_decoder_init_file(argv[1], &dc, &dec) != MA_SUCCESS) {
        std::fprintf(stderr, "File not readable: %s\n", argv[1]);
        return 1;
    }
    const int ch = static_cast<int>(dec.outputChannels);
    const int sr = static_cast<int>(dec.outputSampleRate);
    std::vector<float> pcm, buf(4096 * ch);
    const long long limit = seconds > 0 ? static_cast<long long>(seconds * sr) : -1;
    for (;;) {
        ma_uint64 got = 0;
        ma_decoder_read_pcm_frames(&dec, buf.data(), 4096, &got);
        if (got == 0) break;
        pcm.insert(pcm.end(), buf.begin(), buf.begin() + static_cast<long>(got * ch));
        if (limit > 0 && static_cast<long long>(pcm.size() / ch) >= limit) {
            pcm.resize(static_cast<size_t>(limit * ch));
            break;
        }
    }
    ma_decoder_uninit(&dec);

    wp::Engine engine;
    engine.setSource(std::move(pcm), ch, sr);
    engine.setRate(rate);
    engine.play();

    ma_encoder_config ec = ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, ch, sr);
    ma_encoder enc;
    if (ma_encoder_init_file(argv[2], &ec, &enc) != MA_SUCCESS) {
        std::fprintf(stderr, "Output not writable: %s\n", argv[2]);
        return 1;
    }
    std::vector<float> out(1024 * ch);
    do {  // Befehle wirken erst im ersten render()
        engine.render(out.data(), 1024);
        ma_encoder_write_pcm_frames(&enc, out.data(), 1024, nullptr);
    } while (engine.playing());
    ma_encoder_uninit(&enc);
    std::printf("%s: %.2f s source, tempo %.2f\n", argv[2], engine.duration(), engine.rate());
    return 0;
}
