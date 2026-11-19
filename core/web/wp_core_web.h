/* Web-Ergänzung der C-API (#33). Im Browser läuft der Kern ohne eigenes Audiogerät und ohne Threads in
 * einem AudioWorklet: Das Worklet ruft wp_web_render() je Block auf. Alle Aufrufe kommen aus diesem einen
 * Thread. Steuerung, Wellenform und Metronom heissen wie in wp_core.h (wp_play, wp_seek, wp_metro_*, …).
 * Laden gibt es ohne Dateipfade: Bytes einer MP3-, WAV- oder FLAC-Datei dekodiert der Kern selbst
 * (wp_web_load_encoded); AAC/M4A dekodiert der Browser (decodeAudioData) und gibt das PCM weiter
 * (wp_web_load_pcm). */
#ifndef WP_CORE_WEB_H
#define WP_CORE_WEB_H

#include <stddef.h>

#include "wp_core.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Grösster Block für wp_web_render, in Frames. */
#define WP_WEB_MAX_BLOCK 4096

/* Player mit fester Samplerate (die des AudioContext). NULL, wenn kein Speicher frei ist. */
WP_API wp_player* wp_web_create(int sample_rate);
WP_API int wp_web_sample_rate(wp_player* p);

/* Speicher im WASM-Heap, z. B. für Dateibytes oder PCM, die JS vor dem Laden hineinschreibt. */
WP_API void* wp_web_alloc(size_t bytes);
WP_API void wp_web_free(void* ptr);

/* Dekodiert MP3, WAV oder FLAC aus dem Speicher und setzt den Titel ein (am Anfang, pausiert, ohne Loop).
 * Blockiert, bis alles dekodiert ist. WP_OK oder Fehlercode; bei WP_ERR_UNSUPPORTED_FORMAT kann JS es mit
 * decodeAudioData versuchen. Ein Fehler lässt den bisherigen Titel unverändert spielbar. */
WP_API int wp_web_load_encoded(wp_player* p, const void* data, size_t size);
/* Setzt bereits dekodiertes PCM ein: interleaved, 1 oder mehr Kanäle, beliebige Samplerate (wird auf
 * Stereo und die Rate des Players gewandelt). WP_OK oder Fehlercode. */
WP_API int wp_web_load_pcm(wp_player* p, const float* interleaved, int channels, int frames, int sample_rate);

/* Rendert frames (1–WP_WEB_MAX_BLOCK) Frames Titel und Metronom, interleaved Stereo. Der Zeiger zeigt in
 * einen Puffer des Players, gültig bis zum nächsten Aufruf. Reserviert keinen Speicher. */
WP_API float* wp_web_render(wp_player* p, int frames);

#ifdef __cplusplus
}
#endif
#endif
