/* C-API des Woodshed-Player-Audio-Kerns (#5, #14).
 * Alle Funktionen sind von beliebigen Threads aufrufbar, ausser wp_create/wp_destroy. Steuerbefehle
 * erreichen den Audio-Thread über eine Lock-free-Queue; der Audio-Thread sperrt nicht und
 * reserviert nichts. Zeiten in Sekunden der Originaldatei, Tempo als Faktor (1.0 = Originaltempo).
 */
#ifndef WP_CORE_H
#define WP_CORE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define WP_API __declspec(dllexport)
#else
#define WP_API __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct wp_player wp_player;

/* ---- Fehlercodes (Rückgabe < 0) ---- */
#define WP_OK 0
#define WP_ERR_INVALID_ARGUMENT -1   /* Player oder Pfad fehlt */
#define WP_ERR_FILE_NOT_FOUND -2     /* Datei fehlt */
#define WP_ERR_UNSUPPORTED_FORMAT -3 /* Format unbekannt oder Datei beschädigt */
#define WP_ERR_DEVICE_UNAVAILABLE -4 /* kein Audiogerät */
#define WP_ERR_OUT_OF_MEMORY -5
#define WP_ERR_FILE_UNREADABLE -6         /* keine Leserechte, Ordner statt Datei, Lesefehler */
#define WP_ERR_CANCELLED -7               /* durch ein neueres Laden abgebrochen */
#define WP_ERR_BUSY -8                    /* Befehls-Queue voll */
#define WP_ERR_UNSUPPORTED_SAMPLE_RATE -9 /* rate outside WP_MIN/MAX_SAMPLE_RATE (#76, #97) */
#define WP_ERR_MULTIPLE_TRACKS -10        /* trimming: MP4 with several audio tracks (#120) */
#define WP_ERR_FRAGMENTED -11             /* trimming: fragmented MP4 (#120) */
#define WP_ERR_ENCODER_UNAVAILABLE -12    /* MP3 export: encoder library missing (#141) */
#define WP_ERR_FILE_UNWRITABLE -13        /* MP3 export: output file cannot be written (#141) */

/* Range of sample rates the core accepts, both limits included (#76, #97). A player configured
 * outside it renders silence and answers every load with WP_ERR_UNSUPPORTED_SAMPLE_RATE. */
#define WP_MIN_SAMPLE_RATE 8000
#define WP_MAX_SAMPLE_RATE 192000

/* English text for an error code, static, never NULL. For logs only: the UI shows its own
 * localized text per code (ARB files in the app). */
WP_API const char *wp_error_message(int code);

/* ---- Wiedergabe ---- */
/* Ohne Audiogerät liefert wp_create trotzdem einen Player; Laden meldet dann
 * WP_ERR_DEVICE_UNAVAILABLE. NULL nur, wenn kein Speicher frei ist. */
WP_API wp_player *wp_create(void);
WP_API void wp_destroy(wp_player *p);

/* Laden (MP3, WAV, FLAC). Dekodiert vollständig in den Speicher, im Hintergrund. Ein Fehler lässt
 * den bisherigen Titel unverändert spielbar. Ein neuer Titel steht am Anfang, pausiert, ohne Loop.
 */
#define WP_LOAD_IDLE 0    /* noch nichts geladen */
#define WP_LOAD_RUNNING 1 /* dekodiert gerade */
#define WP_LOAD_READY 2   /* letzter Ladevorgang erfolgreich */
/* Startet das Laden und kehrt sofort zurück; ein noch laufendes Laden wird abgebrochen.
 * WP_OK = gestartet, < 0 = Fehler sofort. */
WP_API int wp_load_async(wp_player *p, const char *path);
/* WP_LOAD_* oder Fehlercode (< 0) des letzten Ladevorgangs. */
WP_API int wp_load_state(wp_player *p);
/* Fortschritt 0–1 des laufenden bzw. letzten Ladevorgangs. */
WP_API double wp_load_progress(wp_player *p);
/* Wartet auf das Ende des laufenden Ladens. WP_OK oder Fehlercode. */
WP_API int wp_load_wait(wp_player *p);
/* Lädt und wartet (blockiert den Aufrufer). WP_OK oder Fehlercode. */
WP_API int wp_load(wp_player *p, const char *path);
/* Dauer einer Datei in Sekunden, ohne sie zu laden (für die Bibliothek). < 0 = Fehlercode. */
WP_API double wp_file_duration(const char *path);
WP_API void wp_play(wp_player *p);
WP_API void wp_pause(wp_player *p);
/* Gerätewechsel (z. B. Kopfhörer ab), Unterbrechung oder Geräteausfall pausieren Wiedergabe und
 * Metronom; die Position bleibt. */
WP_API int wp_is_playing(wp_player *p);
WP_API void wp_seek(wp_player *p, double seconds);
/* 0.1–2.0, Tonhöhe bleibt gleich. Werte ausserhalb werden begrenzt. */
WP_API void wp_set_rate(wp_player *p, double rate);
/* Loop A–B; b <= a + 1 s schaltet den Loop aus. */
WP_API void wp_set_loop(wp_player *p, double a, double b);
WP_API void wp_set_volume(wp_player *p, float volume);
WP_API double wp_position(wp_player *p);
WP_API double wp_duration(wp_player *p);
/* Loop-Durchgänge (#29): zählt, wie oft die Wiedergabe das Loop-Ende erreicht hat und zum
 * Loop-Anfang gesprungen ist. Seek zählt nicht. Der Zähler beginnt nie neu; massgebend ist die
 * Differenz zweier Abfragen. */
WP_API long long wp_loop_passes(wp_player *p);
/* Wellenform des geladenen Titels (#28): teilt [start, end] Sekunden in genau count gleich lange
 * Abschnitte und schreibt je Abschnitt Minimum nach mins[i] und Maximum nach maxs[i] (−1…1, über
 * alle Kanäle). Die Spitzenwerte werden beim Laden einmal berechnet; der Aufruf ist auch für die
 * Übersicht des ganzen Titels schnell. Abschnitte kürzer als 32 Frames zeigen den ganzen
 * 32-Frame-Block. WP_OK oder WP_ERR_INVALID_ARGUMENT (kein Titel, count < 1, start >= end, Bereich
 * ausserhalb des Titels). */
WP_API int wp_waveform(wp_player *p, double start, double end, int count, float *mins, float *maxs);

/* ---- Metronom (#3), läuft mit und ohne Titel ---- */
WP_API void wp_metro_start(wp_player *p); /* beginnt immer mit Takt 1, Schlag 1 */
WP_API void wp_metro_stop(wp_player *p);
WP_API int wp_metro_is_running(wp_player *p);
WP_API void wp_metro_set_bpm(wp_player *p, int bpm); /* 20–300, wird begrenzt */
WP_API int wp_metro_bpm(wp_player *p); /* aktuelles Tempo (ändert sich mit der Steigerung) */
WP_API void wp_metro_set_meter(wp_player *p, int beats_per_bar); /* 2, 3, 4 oder 6 (6/8) */
WP_API void wp_metro_set_subdivision(wp_player *p, int clicks);  /* 1–4 Klicks pro Schlag */
WP_API void wp_metro_set_volume(wp_player *p, float volume);     /* 0–1 */
/* Steigerung nach Takten: alle every_bars Takte um step_bpm. */
WP_API void wp_metro_set_ramp(wp_player *p, int enabled, int start_bpm, int target_bpm,
                              int step_bpm, int every_bars);
/* Steigerung nach Zeit (#23): 1-BPM-Stufen gleichmässig über duration_seconds (1–3600), Wechsel am
 * Taktanfang; danach eine Stufe Ziel, dann wieder Start. Ersetzt die Steigerung nach Takten. */
WP_API void wp_metro_set_ramp_timed(wp_player *p, int enabled, int start_bpm, int target_bpm,
                                    int duration_seconds);

/* ---- Trimming start and end of a file (#116) ---- */
/* Shortest part that may remain, in seconds. */
#define WP_TRIM_MIN_SECONDS 1.0
typedef struct wp_trim_result wp_trim_result;
/* Keeps [start, end] seconds of the audio file in data/size (the whole file) and writes the new
 * file to *out (free it with wp_trim_free). Same format as before: WAV and FLAC exact to the sample
 * (FLAC encoded again, lossless), MP3 at frame boundaries without encoding again (exact with
 * decoders that honour the LAME tag, such as the core's), AAC in ADTS and MP4/M4A (AAC or ALAC,
 * #120; an edit list skips the encoder delay) at the nearest frame boundary. start and end are
 * clamped to the file; at least WP_TRIM_MIN_SECONDS must remain. WP_OK, WP_ERR_INVALID_ARGUMENT (no
 * data or out, range too short, NaN), WP_ERR_UNSUPPORTED_FORMAT (unknown or damaged file),
 * WP_ERR_MULTIPLE_TRACKS, WP_ERR_FRAGMENTED (MP4) or WP_ERR_OUT_OF_MEMORY (also MP4 from 4 GiB on);
 * on an error *out is NULL. */
WP_API int wp_trim(const void *data, size_t size, double start, double end, wp_trim_result **out);
/* Bytes of the trimmed file, valid until wp_trim_free. */
WP_API const void *wp_trim_data(const wp_trim_result *r);
WP_API size_t wp_trim_size(const wp_trim_result *r);
/* Where the new file starts and ends in the old one (seconds); differs from the request only where
 * frame boundaries forced it (ADTS and MP4: at most half a frame, MP3 without LAME tag: not before
 * 12 ms).
 */
WP_API double wp_trim_start(const wp_trim_result *r);
WP_API double wp_trim_end(const wp_trim_result *r);
WP_API void wp_trim_free(wp_trim_result *r);

/* ---- MP3 export (#141) ---- */
/* The encoder is LAME (LGPL), loaded at run time from lame_path (dlopen), never linked. */
#define WP_MP3_SAMPLE_RATE 44100
#define WP_MP3_MIN_BITRATE 32
#define WP_MP3_MAX_BITRATE 320
/* 1 if LAME can be loaded from lame_path, else 0. */
WP_API int wp_mp3_available(const char *lame_path);
/* Decodes in_path (MP3, WAV, FLAC; on Apple devices also M4A/AAC) and writes it to out_path as MP3:
 * CBR at kbps (WP_MP3_MIN_BITRATE … WP_MP3_MAX_BITRATE), WP_MP3_SAMPLE_RATE Hz, the channels of the
 * source (more than two are mixed to two), MPEG frames only (the first is LAME's info frame), no
 * tag. Blocks until done; *cancel (may be NULL) is read between blocks, non-zero cancels; *progress
 * (may be NULL) gets 0 … 1. WP_OK, WP_ERR_INVALID_ARGUMENT, WP_ERR_ENCODER_UNAVAILABLE,
 * WP_ERR_FILE_NOT_FOUND, WP_ERR_UNSUPPORTED_FORMAT, WP_ERR_UNSUPPORTED_SAMPLE_RATE,
 * WP_ERR_OUT_OF_MEMORY, WP_ERR_FILE_UNWRITABLE or WP_ERR_CANCELLED; on an error out_path is
 * removed. */
WP_API int wp_mp3_export(const char *lame_path, const char *in_path, const char *out_path, int kbps,
                         int *cancel, double *progress);

/* ---- Recording: system audio (macOS 14.2+) or microphone (macOS, #113); elsewhere < 0 ---- */
/* Error codes of wp_rec_start (#44); the UI maps each one to its own localized text. */
#define WP_REC_ERR_INVALID_PATH -1  /* no file path */
#define WP_REC_ERR_UNSUPPORTED -2   /* platform without recording or macOS older than 14.2 */
#define WP_REC_ERR_TAP -3           /* system audio tap could not be created */
#define WP_REC_ERR_TAP_FORMAT -4    /* tap format unknown or not float32 */
#define WP_REC_ERR_NO_OUTPUT -5     /* no output device found */
#define WP_REC_ERR_AGGREGATE -6     /* aggregate device could not be created */
#define WP_REC_ERR_OUT_OF_MEMORY -7 /* no memory for the ring buffer */
#define WP_REC_ERR_FILE -8          /* recording file could not be created */
#define WP_REC_ERR_IO_PROC -9       /* IOProc could not be created */
#define WP_REC_ERR_START -10        /* device could not be started */
#define WP_REC_ERR_NO_INPUT -11     /* no input device (microphone) or it could not be opened */
/* #140: threshold or pause of an armed recording out of range */
#define WP_REC_ERR_INVALID_ARGUMENT -12
/* Sources of wp_rec_start_source (#113). */
#define WP_REC_SOURCE_SYSTEM 0 /* system audio without Woodshed Player's own sound, as FLAC */
#define WP_REC_SOURCE_MIC 1    /* default input device of the system, as FLAC */
/* 1 = at least one source can record on this platform, 0 = none. */
WP_API int wp_rec_available(void);
/* 1 = this source can record on this platform, 0 = not (unknown source: 0). */
WP_API int wp_rec_source_available(int source);
/* Starts recording from source into path, as FLAC with 24 bit (#113, #118).
 * macOS asks for the microphone permission itself; without it the microphone delivers silence
 * (wp_rec_only_silence). 0 = ok, < 0 = WP_REC_ERR_* (unknown source: WP_REC_ERR_UNSUPPORTED). */
WP_API int wp_rec_start_source(const char *path, int source);
/* Same as wp_rec_start_source(path, WP_REC_SOURCE_SYSTEM): the system audio as FLAC, without
 * Woodshed Player's own sound. 0 = ok, < 0 = WP_REC_ERR_*. */
WP_API int wp_rec_start(const char *path);
/* #140: states of an armed recording (wp_rec_gate_state). */
#define WP_REC_GATE_OFF 0       /* no recording, or one started without arming */
#define WP_REC_GATE_ARMED 1     /* recording the source, nothing written until the first sound */
#define WP_REC_GATE_RECORDING 2 /* sound came: written from 1 s before the first sound */
#define WP_REC_GATE_DONE 3 /* long enough silence: the file ends the tail after the last sound */
/* #140: like wp_rec_start_source, but armed: the file holds only 1 s before the first sample above
 * threshold_db (dBFS, -120 to 0) up to 2 s after the last one; silence_seconds (0.1 to 60) of
 * uninterrupted silence ends it (WP_REC_GATE_DONE, the caller then calls wp_rec_stop). Shorter
 * pauses stay in the file. 0 = ok, < 0 = WP_REC_ERR_* (settings out of range:
 * WP_REC_ERR_INVALID_ARGUMENT). */
WP_API int wp_rec_start_armed(const char *path, int source, double threshold_db,
                              double silence_seconds);
/* #147: like wp_rec_start_armed, but the file ends tail_seconds (0 to 10) after the last sample
 * above the threshold instead of 2 s (WP_REC_ERR_INVALID_ARGUMENT outside). Stopped during a pause
 * (wp_rec_stop), every armed recording keeps that pause: the file ends where it was stopped. */
WP_API int wp_rec_start_armed_tail(const char *path, int source, double threshold_db,
                                   double silence_seconds, double tail_seconds);
/* #140: WP_REC_GATE_* of the current or last recording. */
WP_API int wp_rec_gate_state(void);
/* #140: seconds written to the file so far (armed: from 1 s before the first sound; otherwise the
 * same as wp_rec_seconds). */
WP_API double wp_rec_kept_seconds(void);
WP_API void wp_rec_stop(void);
WP_API int wp_rec_is_recording(void);
WP_API double wp_rec_seconds(void);
/* Spitzenpegel seit der letzten Abfrage, 0.0–1.0. */
WP_API float wp_rec_level(void);
/* 1 = es kam bisher nur Stille an (z. B. keine Berechtigung oder nichts läuft). */
WP_API int wp_rec_only_silence(void);
/* OSStatus of the last failed wp_rec_start, 0 if the error has none. */
WP_API int wp_rec_os_status(void);
/* English description of the last error, for logs only; the UI uses the code (#44). Never NULL. */
WP_API const char *wp_rec_error(void);

#ifdef __cplusplus
}
#endif
#endif
