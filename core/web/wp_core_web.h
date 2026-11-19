/* Web-Ergänzung der C-API (#33). Im Browser läuft der Kern ohne eigenes Audiogerät und ohne Threads
 * in einem AudioWorklet: Das Worklet ruft wp_web_render() je Block auf. Alle Aufrufe kommen aus
 * diesem einen Thread. Steuerung, Wellenform und Metronom heissen wie in wp_core.h (wp_play,
 * wp_seek, wp_metro_*, …). Laden gibt es ohne Dateipfade: Bytes einer MP3-, WAV- oder FLAC-Datei
 * dekodiert der Kern selbst (wp_web_load_encoded); AAC/M4A dekodiert der Browser (decodeAudioData)
 * und gibt das PCM weiter (wp_web_load_pcm). */
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
WP_API wp_player *wp_web_create(int sample_rate);
WP_API int wp_web_sample_rate(wp_player *p);

/* Speicher im WASM-Heap, z. B. für Dateibytes oder PCM, die JS vor dem Laden hineinschreibt. */
WP_API void *wp_web_alloc(size_t bytes);
WP_API void wp_web_free(void *ptr);

/* Dekodiert MP3, WAV oder FLAC aus dem Speicher und setzt den Titel ein (am Anfang, pausiert, ohne
 * Loop). Blockiert, bis alles dekodiert ist. WP_OK oder Fehlercode; bei WP_ERR_UNSUPPORTED_FORMAT
 * kann JS es mit decodeAudioData versuchen. Ein Fehler lässt den bisherigen Titel unverändert
 * spielbar. */
WP_API int wp_web_load_encoded(wp_player *p, const void *data, size_t size);
/* Setzt bereits dekodiertes PCM ein: interleaved, 1 oder mehr Kanäle, beliebige Samplerate (wird
 * auf Stereo und die Rate des Players gewandelt). WP_OK oder Fehlercode. */
WP_API int wp_web_load_pcm(wp_player *p, const float *interleaved, int channels, int frames,
                           int sample_rate);

/* Loading without blocking the AudioWorklet (#42). A Worker with its own instance of the core
 * decodes the file into a wp_web_track (stereo at the worklet's rate, with waveform); only the
 * finished PCM goes to the worklet, which takes it over in small pieces between render blocks
 * (wp_web_pcm_begin/append/commit). */
typedef struct wp_web_track wp_web_track;

/* Decodes MP3, WAV or FLAC into stereo at sample_rate. NULL on failure, the code goes to *err
 * (WP_ERR_UNSUPPORTED_FORMAT: try decodeAudioData, e.g. AAC/M4A). */
WP_API wp_web_track *wp_web_track_decode(const void *data, size_t size, int sample_rate, int *err);
/* Converts already decoded PCM (interleaved, any channel count and rate) into stereo at dst_rate.
 */
WP_API wp_web_track *wp_web_track_convert(const float *interleaved, int channels, int frames,
                                          int src_rate, int dst_rate, int *err);
/* Interleaved stereo PCM, frames and duration of the track. */
WP_API const float *wp_web_track_data(wp_web_track *t);
WP_API int wp_web_track_frames(wp_web_track *t);
WP_API double wp_web_track_duration(wp_web_track *t);
/* Waveform like wp_waveform. */
WP_API int wp_web_track_waveform(wp_web_track *t, double start, double end, int count, float *mins,
                                 float *maxs);
WP_API void wp_web_track_free(wp_web_track *t);

/* Starts taking over a title of `frames` stereo frames at the player's rate (reserves the memory;
 * an unfinished one is discarded). The current title keeps playing until wp_web_pcm_commit. */
WP_API int wp_web_pcm_begin(wp_player *p, int frames);
/* Appends interleaved stereo frames. WP_ERR_INVALID_ARGUMENT if more than announced or nothing
 * begun. */
WP_API int wp_web_pcm_append(wp_player *p, const float *stereo, int frames);
/* Puts the complete title in place (at the start, paused, without loop), without computing a
 * waveform (wp_waveform reports WP_ERR_INVALID_ARGUMENT afterwards; the worker has it). WP_OK or
 * error code; an error keeps the previous title playable. */
WP_API int wp_web_pcm_commit(wp_player *p);

/* Rendert frames (1–WP_WEB_MAX_BLOCK) Frames Titel und Metronom, interleaved Stereo. Der Zeiger
 * zeigt in einen Puffer des Players, gültig bis zum nächsten Aufruf. Reserviert keinen Speicher. */
WP_API float *wp_web_render(wp_player *p, int frames);

#ifdef __cplusplus
}
#endif
#endif
