# Changelog

Release notes of Woodshed Player, newest version first. This file translates [`CHANGELOG.md`](CHANGELOG.md) (German), which is authoritative. Every entry starts with `## Version X.Y.Z` and has the sections «New, changed, fixed» and «Tests and development» (at least one, in this order); every bullet names its issues. `python3 tools/changelog.py check` checks both files (#139).

## Version 0.9.0

### New, changed, fixed

- **Command line (Mac only, #140):** `woodshed play` loads and plays a title of the library, `woodshed record` arms a recording: it starts with the first sound and ends after a pause; the app talks to the command only through a local socket file. Armed recording is also available in the app.
- **MP3 export (#141):** Export selected titles as MP3, with the year as metadata (`--year` for armed recording).
- **Library (#135, #136, #137):** Titles easier to read, «New folder», view and info in the «⋯» menu; invalid loops are dropped when saving and trimming; a deleted local playlist no longer disturbs the sync.
- **OneDrive removed (#55):** from the docs and the web app.

### Tests and development

- Release workflow with macOS package, web app and release notes in two languages (#139).
- Test page and test program K0 for the direct connection between devices (#52).
- Nightly mutation tests with a cache per source state (#138); a broken connection of the command line on Linux without an unhandled error (#140).

## Version 0.8.2

### New, changed, fixed

- **Window (#129, #130):** The width of the library sidebar can be changed with the mouse. The window has a default and a minimum size and opens at the size last chosen.
- **Metronome (#133):** Two columns on the desktop.

### Tests and development

- Own temp folder per run of the C API tests (#132); the keyboard shortcut test keeps the app in front (#134).

## Version 0.8.1

### New, changed, fixed

- **Google sign-in in the web app (#131):** Google's answer is taken over when the web app starts.

### Tests and development

- Skipped tests count as failures in CI, with a reason also on Windows (#125).
- Rules for the test-agent against superfluous tests; its report names rule and breach also for exceptions (#126).
- Findings of the random tests as named regression tests (#127), time limit for single Dart tests (#128), start check of the web app with the library collapsed (#123).

## Version 0.8.0

First version of the new Flutter app with a C++ audio core for macOS, iPhone/iPad and the browser.

### New, changed, fixed

- **Library and playlists (#114, #121, #122, #123, #124):** Playlists next to folders; drag files from outside onto playlists and folders; select several tracks, move them together and delete them with the Delete key; sort playlists by title, artist, duration or date added; the library is collapsed by default in the player area.
- **Areas (#115):** Player, practice and metronome.
- **Recording and trimming (#113, #116, #118, #120):** Microphone and system audio recording as FLAC; trim the start and end of a track, also for M4A.
- **Sync via Google Drive (#53, #54, #65, #98, #104, #107):** Sign-in on the Mac through the system's sign-in window, one file per device, a question before offline changes to tracks and folders are lost, restoring a damaged `state.json` in the cloud, protection against revived deleted entries; starting with a saved sign-in no longer hangs.
- **Web app (#39, #71, #72, #82, #109, #110):** Offline start, Media Session, audio cache and an «Add to Home Screen» hint that stays away once closed; the screen stays on while practising; no missing font file, replacement characters instead of loaded fallback fonts, no Dropbox hosts in the CSP any more.
- **Licence notices (#119):** The licence texts of the core libraries are in the app.
- **Playback and files (#70, #73, #75, #76, #81, #91, #93, #96, #97, #105, #106):** Correct position after a seek while paused and after seek with play; metronome when bar and subdivision change at once; long tracks load with less memory; sample rate limits (at most 192 kHz); readable metadata despite damaged tags; out of memory in the WASM core without abort; file path ending with a dot.
- **Cleaned up (#84, #111, #117):** Repair dialog of the damaged `state.json` removed, Dropbox leftovers removed, proposal to offer iPhone and iPad only as a web app.

### Tests and development

- Test strategy, formatting and code hygiene (#7), test coverage per part (#8), audio reference cases (#9), random tests, fuzzing and golden files (#10), test quality overview page (#12), UI tests and GitHub workflow (#13).
- Sanitizers and real-time safety in the core (#57, #63, #101, #102, #103), network-free check (#58), performance and load tests (#59).
- Mutation tests (#11) with mutants detected or excluded with a reason (#61, #108).
- Contract native and WASM (#77, #80, #94, #100), fuzzing of the C API and web API, also against the WASM core (#66, #67, #85, #86, #88).
- More stable tests by waiting for states instead of fixed pauses (#62, #78, #92, #95), testable parts of recording (#68), UI smoke test on the iOS simulator (#99).
- Workflow: actionlint (#64), tool tests in the hook (#69), fixed Emscripten version in the cache (#79, #89), web app built only once (#83), time limit for web tests (#112), a tag push publishes through a run on `main` (#41), test page M0 for the Google sign-in (#52).
