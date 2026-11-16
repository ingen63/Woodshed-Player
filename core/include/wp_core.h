/* C-API des Woodshed-Player-Audio-Kerns (Prototyp #5).
 * Alle Funktionen sind von beliebigen Threads aufrufbar, ausser wp_create/wp_destroy.
 * Zeiten in Sekunden der Originaldatei, Tempo als Faktor (1.0 = Originaltempo). */
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

/* ---- Wiedergabe ---- */
WP_API wp_player* wp_create(void);
WP_API void wp_destroy(wp_player* p);
/* Lädt eine Audiodatei (MP3, WAV, FLAC) vollständig in den Speicher. 0 = ok, sonst Fehlercode < 0. */
WP_API int wp_load(wp_player* p, const char* path);
WP_API void wp_play(wp_player* p);
WP_API void wp_pause(wp_player* p);
WP_API int wp_is_playing(wp_player* p);
WP_API void wp_seek(wp_player* p, double seconds);
/* 0.1–2.0, Tonhöhe bleibt gleich. Werte ausserhalb werden begrenzt. */
WP_API void wp_set_rate(wp_player* p, double rate);
/* Loop A–B; b <= a + 1 s schaltet den Loop aus. */
WP_API void wp_set_loop(wp_player* p, double a, double b);
WP_API void wp_set_volume(wp_player* p, float volume);
WP_API double wp_position(wp_player* p);
WP_API double wp_duration(wp_player* p);

/* ---- Metronom (#3), läuft mit und ohne Titel ---- */
WP_API void wp_metro_start(wp_player* p);  /* beginnt immer mit Takt 1, Schlag 1 */
WP_API void wp_metro_stop(wp_player* p);
WP_API int wp_metro_is_running(wp_player* p);
WP_API void wp_metro_set_bpm(wp_player* p, int bpm);  /* 20–300, wird begrenzt */
WP_API int wp_metro_bpm(wp_player* p);                /* aktuelles Tempo (ändert sich mit der Steigerung) */
WP_API void wp_metro_set_meter(wp_player* p, int beats_per_bar);    /* 2, 3, 4 oder 6 (6/8) */
WP_API void wp_metro_set_subdivision(wp_player* p, int clicks);     /* 1–4 Klicks pro Schlag */
WP_API void wp_metro_set_volume(wp_player* p, float volume);        /* 0–1 */
WP_API void wp_metro_set_ramp(wp_player* p, int enabled, int start_bpm, int target_bpm, int step_bpm,
                              int every_bars);

/* ---- Aufnahme des Systemtons (nur macOS 14.2+, sonst Rückgabe < 0) ---- */
/* 1 = auf dieser Plattform verfügbar, 0 = nicht verfügbar. */
WP_API int wp_rec_available(void);
/* Startet die Aufnahme als WAV-Datei. Der eigene Ton von Woodshed Player wird nicht mit aufgenommen.
 * 0 = ok, < 0 = Fehler (siehe wp_rec_error). */
WP_API int wp_rec_start(const char* wav_path);
WP_API void wp_rec_stop(void);
WP_API int wp_rec_is_recording(void);
WP_API double wp_rec_seconds(void);
/* Spitzenpegel seit der letzten Abfrage, 0.0–1.0. */
WP_API float wp_rec_level(void);
/* 1 = es kam bisher nur Stille an (z. B. keine Berechtigung oder nichts läuft). */
WP_API int wp_rec_only_silence(void);
WP_API const char* wp_rec_error(void);

#ifdef __cplusplus
}
#endif
#endif
