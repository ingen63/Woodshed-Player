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

/* Player with a fixed sample rate (the AudioContext's). NULL only if there is no free memory.
 * Below WP_MIN_SAMPLE_RATE (#76) or above WP_MAX_SAMPLE_RATE (#97) the player stays silent and
 * every load reports WP_ERR_UNSUPPORTED_SAMPLE_RATE. */
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
 * (WP_ERR_UNSUPPORTED_FORMAT: try decodeAudioData, e.g. AAC/M4A; WP_ERR_UNSUPPORTED_SAMPLE_RATE:
 * sample_rate below WP_MIN_SAMPLE_RATE or above WP_MAX_SAMPLE_RATE). */
WP_API wp_web_track *wp_web_track_decode(const void *data, size_t size, int sample_rate, int *err);
/* Converts already decoded PCM (interleaved, any channel count and rate) into stereo at dst_rate.
 * Either rate below WP_MIN_SAMPLE_RATE or above WP_MAX_SAMPLE_RATE (#97) gives
 * WP_ERR_UNSUPPORTED_SAMPLE_RATE. */
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

/* Recording in the browser (#157): no device, threads or files. A Worker feeds the microphone block
 * by block (wp_web_rec_input, wp_web_rec_feed), stores the encoded FLAC piece by piece
 * (wp_web_rec_out at wp_web_rec_out_offset, then wp_web_rec_take) and finally writes
 * wp_web_rec_header over the start of the file. Armed, the same sound gate as natively decides what
 * is kept (WP_REC_GATE_*, see wp_rec_start_armed). FLAC with 24 bits, like every native recording.
 */
typedef struct wp_web_rec wp_web_rec;

/* Starts a recording of `channels` (1–8) at `sample_rate`. With `armed` != 0 only sound is kept: 1
 * s before the first sample above threshold_db up to tail_seconds after the last; silence_seconds
 * of silence ends it (WP_REC_GATE_DONE). NULL on failure, the code goes to *err:
 * WP_REC_ERR_INVALID_ARGUMENT (rate, channels or settings out of range), WP_REC_ERR_OUT_OF_MEMORY.
 */
WP_API wp_web_rec *wp_web_rec_create(int sample_rate, int channels, int armed, double threshold_db,
                                     double silence_seconds, double tail_seconds, int *err);
/* Buffer for up to WP_WEB_MAX_BLOCK interleaved frames, filled by the caller before
 * wp_web_rec_feed. */
WP_API float *wp_web_rec_input(wp_web_rec *r);
/* Records `frames` (1–WP_WEB_MAX_BLOCK) frames from the input buffer. 0 = ok, WP_REC_ERR_FILE if
 * the encoder failed or the recording is over (cut), WP_REC_ERR_INVALID_ARGUMENT for a bad count.
 */
WP_API int wp_web_rec_feed(wp_web_rec *r, int frames);
/* Ends the recording (a held pause stays, the rest is encoded, the header gets length and MD5). 0 =
 * ok or WP_REC_ERR_FILE. */
WP_API int wp_web_rec_finish(wp_web_rec *r);
/* Encoded bytes not taken yet, and their offset in the file. */
WP_API const void *wp_web_rec_out(wp_web_rec *r);
WP_API size_t wp_web_rec_out_size(wp_web_rec *r);
WP_API double wp_web_rec_out_offset(wp_web_rec *r);
/* The bytes of wp_web_rec_out are stored; drops them. */
WP_API void wp_web_rec_take(wp_web_rec *r);
/* The bytes of the last wp_web_rec_take could not be stored (storage full): ends the recording, the
 * header counts only what was stored before. Returns the length the file must be cut to. */
WP_API double wp_web_rec_cut(wp_web_rec *r);
/* Start of the file as it must stand at offset 0 (final after wp_web_rec_finish or wp_web_rec_cut).
 */
WP_API const void *wp_web_rec_header(wp_web_rec *r);
WP_API size_t wp_web_rec_header_size(wp_web_rec *r);
/* WP_REC_GATE_* (WP_REC_GATE_OFF without arming). */
WP_API int wp_web_rec_gate(wp_web_rec *r);
/* Seconds fed so far, and seconds kept for the file. */
WP_API double wp_web_rec_seconds(wp_web_rec *r);
WP_API double wp_web_rec_kept_seconds(wp_web_rec *r);
/* Peak level since the last call, 0–1. */
WP_API float wp_web_rec_level(wp_web_rec *r);
/* 1 while only silence came so far. */
WP_API int wp_web_rec_only_silence(wp_web_rec *r);
WP_API void wp_web_rec_free(wp_web_rec *r);

/* Rendert frames (1–WP_WEB_MAX_BLOCK) Frames Titel und Metronom, interleaved Stereo. Der Zeiger
 * zeigt in einen Puffer des Players, gültig bis zum nächsten Aufruf. Reserviert keinen Speicher. */
WP_API float *wp_web_render(wp_player *p, int frames);

#ifdef __cplusplus
}
#endif
#endif
