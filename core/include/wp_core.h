/* C-API des Woodshed-Player-Audio-Kerns (#5, #14).
 * Alle Funktionen sind von beliebigen Threads aufrufbar, ausser wp_create/wp_destroy. Steuerbefehle
 * erreichen den Audio-Thread über eine Lock-free-Queue; der Audio-Thread sperrt nicht und
 * reserviert nichts. Zeiten in Sekunden der Originaldatei, Tempo als Faktor (1.0 = Originaltempo).
 */
#ifndef WP_CORE_H
#define WP_CORE_H

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

/* Range of sample rates the core accepts, both limits included (#76, #97). A player configured
 * outside it renders silence and answers every load with WP_ERR_UNSUPPORTED_SAMPLE_RATE. */
#define WP_MIN_SAMPLE_RATE 8000
#define WP_MAX_SAMPLE_RATE 96000

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

/* ---- Aufnahme des Systemtons (nur macOS 14.2+, sonst Rückgabe < 0) ---- */
/* Error codes of wp_rec_start (#44); the UI maps each one to its own localized text. */
#define WP_REC_ERR_INVALID_PATH -1  /* no file path */
#define WP_REC_ERR_UNSUPPORTED -2   /* platform without recording or macOS older than 14.2 */
#define WP_REC_ERR_TAP -3           /* system audio tap could not be created */
#define WP_REC_ERR_TAP_FORMAT -4    /* tap format unknown or not float32 */
#define WP_REC_ERR_NO_OUTPUT -5     /* no output device found */
#define WP_REC_ERR_AGGREGATE -6     /* aggregate device could not be created */
#define WP_REC_ERR_OUT_OF_MEMORY -7 /* no memory for the ring buffer */
#define WP_REC_ERR_FILE -8          /* WAV file could not be created */
#define WP_REC_ERR_IO_PROC -9       /* IOProc could not be created */
#define WP_REC_ERR_START -10        /* device could not be started */
/* 1 = auf dieser Plattform verfügbar, 0 = nicht verfügbar. */
WP_API int wp_rec_available(void);
/* Startet die Aufnahme als WAV-Datei. Der eigene Ton von Woodshed Player wird nicht mit
 * aufgenommen. 0 = ok, < 0 = WP_REC_ERR_*. */
WP_API int wp_rec_start(const char *wav_path);
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
