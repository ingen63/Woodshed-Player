cmake_minimum_required(VERSION 3.20)
project(wp_core LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# #7: compile_commands.json for clang-tidy (make lint)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
# Statische Teile landen in der geteilten Bibliothek wp_core (Linux, Android).
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Plattformen: macOS und iOS werden gebaut und getestet; Windows, Linux und Android sind konfiguriert
# (Bau dort in #13). iOS: cmake -S core -B core/build-ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS
# Android: cmake -S core -B core/build-android -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26
# Web (#33): emcmake cmake -S core -B core/build-wasm -DCMAKE_BUILD_TYPE=Release && cmake --build core/build-wasm
#   && ctest --test-dir core/build-wasm   (Tests laufen unter Node.js, Ergebnis: wp_core_web.wasm fürs AudioWorklet)
if(APPLE)
  enable_language(OBJC OBJCXX)
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(CMAKE_OSX_DEPLOYMENT_TARGET 17.0 CACHE STRING "")
  else()
    set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0 CACHE STRING "")
  endif()
endif()
if(MSVC)
  add_compile_options(/utf-8 /W3)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()
find_package(Threads REQUIRED)

# #9/AK7: no fused multiply-add, so native and web cores render the same samples. Apple Clang
# contracts a * b + c into one FMA instruction on arm64 (-ffp-contract=on), WebAssembly has none;
# the time stretch amplified that rounding difference up to 2e-2 at rate 0.1. Without contraction
# the outputs are bit-identical. MSVC does not contract by default (/fp:precise). The Flutter
# plugin sets the same flag (app/packages/wp_core/*/wp_core.podspec).
if(NOT MSVC)
  add_compile_options(-ffp-contract=off)
endif()

set(WP_THIRD_PARTY ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# #7: warnings are errors in our own code. Third-party code (miniaudio, signalsmith) is compiled
# without these flags and its headers are included as SYSTEM, so their warnings do not count.
option(WP_STRICT_WARNINGS "Treat warnings in our own code as errors" ON)
function(wp_strict_warnings target)
  if(WP_STRICT_WARNINGS AND NOT MSVC)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
  endif()
endfunction()

# #8: line coverage with llvm-cov (make coverage). Instruments every target of this build; the
# report keeps only our own sources (tools/coverage_check.dart reads tools/coverage-min).
option(WP_COVERAGE "Instrument the build for llvm-cov" OFF)
if(WP_COVERAGE)
  add_compile_options(-fprofile-instr-generate -fcoverage-mapping)
  add_link_options(-fprofile-instr-generate)
endif()

# #57: sanitizers (make sanitize, make sanitize-thread). WP_SANITIZE is a -fsanitize list, e.g.
# "address,undefined" or "thread". It instruments every target of this build, third-party code
# included, so findings there show up too (they are reported, not fixed there). Any finding aborts
# the program (-fno-sanitize-recover), so the test fails. Fuzz targets (#10) inherit these flags
# and only add "fuzzer" for their own target. Suppressions: tests/sanitizer/*.supp, each with a
# reason (docs/TESTS.md).
set(WP_SANITIZE "" CACHE STRING "Sanitizers to build with, e.g. address,undefined or thread")
if(WP_SANITIZE)
  add_compile_options(-fsanitize=${WP_SANITIZE} -fno-sanitize-recover=all -fno-omit-frame-pointer
    -g)
  add_link_options(-fsanitize=${WP_SANITIZE})
  add_compile_definitions(WP_SANITIZED=1)
endif()

# #10/AK4: libFuzzer targets (make fuzz, tests/fuzz/fuzz.cmake). Needs clang with libFuzzer
# (Homebrew llvm on macOS, Apple Clang has none). Instruments all code of the build for coverage;
# the fuzz programs themselves add -fsanitize=fuzzer. Used together with WP_SANITIZE.
option(WP_FUZZ "Build the libFuzzer targets (clang with libFuzzer)" OFF)
if(WP_FUZZ)
  add_compile_options(-fsanitize=fuzzer-no-link)
endif()

# #11: mutation build with Mull (make mutants, app/tool/mutants.dart, docs/TESTS.md). WP_MULL_PLUGIN
# is the compiler plugin of Mull (mull-ir-frontend-<LLVM major>), it needs clang of the same major
# version (Homebrew llvm, on Linux clang-<n>). Only our own targets load it (wp_mutate); the plugin
# reads the configuration written below (tests/mutants/mull.yml; make mutants-diff adds the changed
# lines, WP_MULL_RANGES).
# Every test program gets the memory guard (tests/mutants/memory_guard.cpp, #11/AK4).
set(WP_MULL_PLUGIN "" CACHE FILEPATH "Mull compiler plugin; builds the mutation test programs")
set(WP_MULL_RANGES "" CACHE FILEPATH
  "Only mutate these lines (make mutants-diff): one <path>:<first>-<last> per line")
if(WP_MULL_PLUGIN)
  # The effective configuration: tests/mutants/mull.yml and the line ranges of a diff run. Written
  # only when it changes, so the sources compile again only then. Mull's AST check reads the command
  # line recorded with -grecord-command-line and splits it at spaces; app/tool/mutants.dart therefore
  # configures this build through a link without spaces when the project path has one.
  file(READ ${CMAKE_CURRENT_SOURCE_DIR}/tests/mutants/mull.yml wp_mull_yml)
  if(WP_MULL_RANGES)
    file(SHA256 ${WP_MULL_RANGES} wp_mull_ranges_hash)
    string(APPEND wp_mull_yml "mutationRanges: '${WP_MULL_RANGES}'  # ${wp_mull_ranges_hash}\n")
  endif()
  set(WP_MULL_CONFIG ${CMAKE_BINARY_DIR}/mull.yml)
  file(CONFIGURE OUTPUT ${WP_MULL_CONFIG} CONTENT "${wp_mull_yml}" @ONLY)
  set(CMAKE_C_COMPILER_LAUNCHER ${CMAKE_COMMAND} -E env "MULL_CONFIG=${WP_MULL_CONFIG}")
  set(CMAKE_CXX_COMPILER_LAUNCHER ${CMAKE_C_COMPILER_LAUNCHER})
  set(CMAKE_OBJCXX_COMPILER_LAUNCHER ${CMAKE_C_COMPILER_LAUNCHER})
endif()
function(wp_mutate target)
  if(WP_MULL_PLUGIN)
    target_compile_options(${target} PRIVATE -fpass-plugin=${WP_MULL_PLUGIN} -g -grecord-command-line)
    # a new configuration (another diff) compiles the mutated sources again
    get_target_property(srcs ${target} SOURCES)
    set_source_files_properties(${srcs} TARGET_DIRECTORY ${target} PROPERTIES
      OBJECT_DEPENDS "${WP_MULL_CONFIG}")
  endif()
endfunction()

# #113: libFLAC sources (encoder and decoder of native FLAC); #116: also in the web core (trimming)
set(WP_FLAC ${WP_THIRD_PARTY}/flac)
set(WP_FLAC_SOURCES
  ${WP_FLAC}/src/libFLAC/bitmath.c ${WP_FLAC}/src/libFLAC/bitreader.c
  ${WP_FLAC}/src/libFLAC/bitwriter.c ${WP_FLAC}/src/libFLAC/cpu.c ${WP_FLAC}/src/libFLAC/crc.c
  ${WP_FLAC}/src/libFLAC/fixed.c ${WP_FLAC}/src/libFLAC/float.c ${WP_FLAC}/src/libFLAC/format.c
  ${WP_FLAC}/src/libFLAC/lpc.c ${WP_FLAC}/src/libFLAC/md5.c ${WP_FLAC}/src/libFLAC/memory.c
  ${WP_FLAC}/src/libFLAC/stream_decoder.c ${WP_FLAC}/src/libFLAC/stream_encoder.c
  ${WP_FLAC}/src/libFLAC/stream_encoder_framing.c ${WP_FLAC}/src/libFLAC/window.c)

if(EMSCRIPTEN)
  include(web/web.cmake)  # eigener Zweig: Tests unter Node.js, Kern fürs AudioWorklet
  return()
endif()

# Wiedergabe-Logik ohne Audiogerät (für Tests und Offline-Rendering)
add_library(wp_engine STATIC src/engine.cpp src/metronome.cpp src/waveform.cpp)
target_include_directories(wp_engine PUBLIC src)
target_include_directories(wp_engine SYSTEM PUBLIC
  ${WP_THIRD_PARTY}/signalsmith-stretch/include
  ${WP_THIRD_PARTY}/signalsmith-linear/include)
wp_strict_warnings(wp_engine)
wp_mutate(wp_engine)

add_library(wp_miniaudio STATIC src/miniaudio_impl.c)
target_include_directories(wp_miniaudio SYSTEM PUBLIC ${WP_THIRD_PARTY}/miniaudio)
target_include_directories(wp_miniaudio PUBLIC src)
target_link_libraries(wp_miniaudio PUBLIC Threads::Threads)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  # Auf iOS als Objective-C, damit miniaudio die AVAudioSession einrichten kann.
  set_source_files_properties(src/miniaudio_impl.c PROPERTIES LANGUAGE OBJC)
  target_link_libraries(wp_miniaudio PUBLIC "-framework Foundation" "-framework AVFoundation"
    "-framework CoreAudio" "-framework AudioToolbox")
elseif(APPLE)
  target_link_libraries(wp_miniaudio PUBLIC "-framework CoreFoundation" "-framework CoreAudio" "-framework AudioToolbox")
elseif(ANDROID)
  target_link_libraries(wp_miniaudio PUBLIC dl m)  # AAudio/OpenSL ES lädt miniaudio zur Laufzeit
elseif(UNIX)
  target_link_libraries(wp_miniaudio PUBLIC dl m)  # ALSA/PulseAudio lädt miniaudio zur Laufzeit
endif()
# Windows: WASAPI/DirectSound lädt miniaudio zur Laufzeit, keine weiteren Bibliotheken.

# Player ohne Audiogerät: Laden im Hintergrund, Fehlercodes, Gerätewechsel (#14)
add_library(wp_playercore STATIC src/player_core.cpp)
target_link_libraries(wp_playercore PUBLIC wp_engine wp_miniaudio Threads::Threads)
wp_strict_warnings(wp_playercore)
wp_mutate(wp_playercore)

# #113: libFLAC (third_party/flac, BSD-3-Clause), only native FLAC: no Ogg, no threads, no SIMD.
# Its config.h is ours (src/flac_config). Third-party code: no strict warnings, headers as SYSTEM.
add_library(wp_flac STATIC ${WP_FLAC_SOURCES})
if(WIN32)
  target_sources(wp_flac PRIVATE ${WP_FLAC}/src/share/win_utf8_io/win_utf8_io.c)
endif()
target_compile_definitions(wp_flac PUBLIC FLAC__NO_DLL PRIVATE HAVE_CONFIG_H)
target_include_directories(wp_flac SYSTEM PUBLIC ${WP_FLAC}/include)
target_include_directories(wp_flac SYSTEM PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src/flac_config
  ${WP_FLAC}/src/libFLAC/include)
set_target_properties(wp_flac PROPERTIES C_VISIBILITY_PRESET hidden)
if(UNIX)
  target_link_libraries(wp_flac PRIVATE m)
endif()

# #113: FLAC writer on libFLAC (recording, #116: trimming)
add_library(wp_flacwriter STATIC src/flac_writer.cpp)
target_include_directories(wp_flacwriter PUBLIC src)
target_link_libraries(wp_flacwriter PUBLIC wp_flac)
wp_strict_warnings(wp_flacwriter)
wp_mutate(wp_flacwriter)

# #116: trimming start and end of a file in memory (WAV, FLAC, MP3, ADTS; #120: MP4)
add_library(wp_trim STATIC src/trim.cpp src/trim_mp4.cpp)
target_include_directories(wp_trim PUBLIC include src)
target_link_libraries(wp_trim PUBLIC wp_miniaudio wp_flacwriter)
wp_strict_warnings(wp_trim)
wp_mutate(wp_trim)

# #68: platform-independent part of the recording (ring buffer, writer thread, WAV or FLAC file,
# level, #113: microphone through miniaudio), tested without an audio device; recorder_mac.mm only
# drives Core Audio.
add_library(wp_reccore STATIC src/recorder_core.cpp src/sound_gate.cpp)
target_include_directories(wp_reccore PUBLIC include)
target_link_libraries(wp_reccore PUBLIC wp_miniaudio wp_flacwriter Threads::Threads)
wp_strict_warnings(wp_reccore)
wp_mutate(wp_reccore)

# Kern mit C-API (wp_core.h)
if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(WP_RECORDER src/recorder_mac.mm)
else()
  set(WP_RECORDER src/recorder_stub.cpp)
endif()
add_library(wp_core SHARED src/player.cpp src/trim_api.cpp ${WP_RECORDER})
target_include_directories(wp_core PUBLIC include)
target_link_libraries(wp_core PRIVATE wp_playercore wp_trim)
if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  target_link_libraries(wp_core PRIVATE wp_reccore)
endif()
set_target_properties(wp_core PROPERTIES CXX_VISIBILITY_PRESET hidden)
wp_strict_warnings(wp_core)
wp_mutate(wp_core)
if(APPLE)
  target_compile_options(wp_core PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
  target_link_libraries(wp_core PRIVATE "-framework Foundation")
endif()

# Werkzeuge und Tests nur auf Rechnern (nicht für iOS)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  return()
endif()

# Werkzeug: Datei offline mit Tempo rendern (Hörvergleich)
add_executable(wp_render tools/wp_render.cpp)
target_link_libraries(wp_render PRIVATE wp_engine wp_miniaudio)
wp_strict_warnings(wp_render)

# Tests
enable_testing()
add_executable(engine_tests tests/engine_tests.cpp)
target_link_libraries(engine_tests PRIVATE wp_engine Threads::Threads)
wp_strict_warnings(engine_tests)
add_test(NAME engine_tests COMMAND engine_tests)

add_executable(metronome_tests tests/metronome_tests.cpp)
target_link_libraries(metronome_tests PRIVATE wp_engine)
wp_strict_warnings(metronome_tests)
add_test(NAME metronome_tests COMMAND metronome_tests)

add_executable(waveform_tests tests/waveform_tests.cpp)
target_link_libraries(waveform_tests PRIVATE wp_engine)
wp_strict_warnings(waveform_tests)
add_test(NAME waveform_tests COMMAND waveform_tests)

add_executable(player_tests tests/player_tests.cpp)
target_link_libraries(player_tests PRIVATE wp_playercore)
target_include_directories(player_tests PRIVATE include)
target_compile_definitions(player_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(player_tests)
add_test(NAME player_tests COMMAND player_tests)

# #68: recording without an audio device (ring buffer, WAV file, level, tap layouts); #113: FLAC
# file loaded again by the core (wp_playercore), microphone on the null backend
add_executable(recorder_tests tests/recorder_tests.cpp)
target_link_libraries(recorder_tests PRIVATE wp_reccore wp_playercore)
wp_strict_warnings(recorder_tests)
add_test(NAME recorder_tests COMMAND recorder_tests)

# #140: armed recording, sound and silence detection with generated sine and silence
add_executable(sound_gate_tests tests/sound_gate_tests.cpp)
target_link_libraries(sound_gate_tests PRIVATE wp_reccore wp_playercore)
wp_strict_warnings(sound_gate_tests)
add_test(NAME sound_gate_tests COMMAND sound_gate_tests)

# #116: trimming WAV, FLAC, MP3 and ADTS; the results decoded again by the core (wp_playercore)
add_executable(trim_tests tests/trim_tests.cpp src/trim_api.cpp)
target_link_libraries(trim_tests PRIVATE wp_trim wp_playercore)
target_compile_definitions(trim_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(trim_tests)
add_test(NAME trim_tests COMMAND trim_tests)

# #120: trimming MP4/M4A; on Apple platforms the results are also decoded by the system decoder
add_executable(trim_mp4_tests tests/trim_mp4_tests.cpp src/trim_api.cpp)
target_link_libraries(trim_mp4_tests PRIVATE wp_trim)
if(APPLE)
  target_link_libraries(trim_mp4_tests PRIVATE "-framework AudioToolbox" "-framework CoreFoundation")
endif()
target_compile_definitions(trim_mp4_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(trim_mp4_tests)
add_test(NAME trim_mp4_tests COMMAND trim_mp4_tests)

# #61: the device shell (src/player.cpp) compiled into the test itself, on the null device
add_executable(device_tests tests/device_tests.cpp)
target_link_libraries(device_tests PRIVATE wp_playercore)
target_include_directories(device_tests PRIVATE include)
target_compile_definitions(device_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(device_tests)
wp_mutate(device_tests)
add_test(NAME device_tests COMMAND device_tests)

# #8: the C API (src/player.cpp) through the shared library, as the Dart binding calls it
add_executable(capi_tests tests/capi_tests.cpp)
target_link_libraries(capi_tests PRIVATE wp_core)
target_compile_definitions(capi_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(capi_tests)
add_test(NAME capi_tests COMMAND capi_tests)
# #13: the same cases on miniaudio's null device (WP_AUDIO_BACKEND=null), never skipped
add_test(NAME capi_null_backend_tests COMMAND capi_tests --null-backend)

# #57/AK4: no allocation and no blocking lock in the render path (Player::render)
add_executable(realtime_tests tests/realtime_tests.cpp)
target_link_libraries(realtime_tests PRIVATE wp_playercore ${CMAKE_DL_LIBS})
wp_strict_warnings(realtime_tests)
add_test(NAME realtime_tests COMMAND realtime_tests)

# #59: performance and load tests (make bench, nightly). Always built, so format, lint and the
# compiler see them; registered only with WP_BENCH=ON and the label «bench», so ctest in make test
# never runs them. They write a 605 MiB WAV to the temp folder and need about 1.5 GiB of memory.
add_executable(bench_tests tests/bench_tests.cpp)
target_link_libraries(bench_tests PRIVATE wp_playercore)
wp_strict_warnings(bench_tests)
option(WP_BENCH "Register the performance and load tests (#59)" OFF)
if(WP_BENCH)
  add_test(NAME bench_stretch COMMAND bench_tests stretch)
  add_test(NAME bench_long_file COMMAND bench_tests long-file)
  add_test(NAME bench_memory_limit COMMAND bench_tests memory-limit)
  add_test(NAME bench_reserve_fallback COMMAND bench_tests reserve-fallback)
  set_tests_properties(bench_stretch bench_long_file bench_memory_limit bench_reserve_fallback
    PROPERTIES LABELS bench RUN_SERIAL ON TIMEOUT 900)
endif()

# #9: audio reference cases against the offline C API, natively and under WASM (tests/reference.cmake)
include(tests/reference.cmake)

# #10: fuzz targets, replay of regression inputs and start corpus in every build
include(tests/fuzz/fuzz.cmake)

# #11: test programs of the mutation run (app/tool/mutants.dart runs each with mull-runner). Each
# gets the memory guard and the fast mutant switch (tests/mutants/mutant_switch.cpp, #11/AK3);
# mutants_selftest checks that an endless loop with and without growing
# memory ends as killed or timeout (#11/AK4).
if(WP_MULL_PLUGIN)
  set(WP_MUTANT_TESTS engine_tests metronome_tests waveform_tests player_tests recorder_tests
    sound_gate_tests capi_tests
    device_tests realtime_tests reference_tests trim_tests fuzz_decoder_replay fuzz_capi_replay
    fuzz_trim_replay)
  foreach(t IN LISTS WP_MUTANT_TESTS)
    target_sources(${t} PRIVATE tests/mutants/memory_guard.cpp tests/mutants/mutant_switch.cpp)
  endforeach()
  add_executable(mutants_selftest tests/mutants/selftest.cpp tests/mutants/memory_guard.cpp
    tests/mutants/mutant_switch.cpp)
  set_source_files_properties(tests/mutants/selftest.cpp PROPERTIES
    COMPILE_OPTIONS "-fpass-plugin=${WP_MULL_PLUGIN};-g;-grecord-command-line"
    OBJECT_DEPENDS "${WP_MULL_CONFIG}")
  wp_strict_warnings(mutants_selftest)
  # #103: clang 18 (the Mull package of the workflow job) reports NULL + 0 in C as pointer-overflow;
  # miniaudio does that when a converter needs no heap (ma_offset_ptr(NULL, 0)). Newer clang no longer
  # reports it (C2y makes it defined), so make sanitize and the local mutation runs stay silent. Only
  # this third-party translation unit skips the check; our own code keeps every UBSan check.
  if(WP_SANITIZE MATCHES "undefined")
    target_compile_options(wp_miniaudio PRIVATE -fno-sanitize=pointer-overflow)
  endif()
endif()

# #57: in a sanitizer build every test runs with these options; a finding ends the test with a
# non-zero exit code. Suppression files in tests/sanitizer/ (each entry with a reason).
if(WP_SANITIZE)
  set(WP_SAN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/tests/sanitizer)
  set(WP_SAN_ENV
    "UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1:suppressions='${WP_SAN_DIR}/ubsan.supp'"
    "TSAN_OPTIONS=halt_on_error=1:second_deadlock_stack=1:suppressions='${WP_SAN_DIR}/tsan.supp'")
  if(APPLE)
    # LeakSanitizer is not supported with ASan on macOS
    list(APPEND WP_SAN_ENV "ASAN_OPTIONS=halt_on_error=1:detect_stack_use_after_return=1")
  else()
    list(APPEND WP_SAN_ENV
      "ASAN_OPTIONS=halt_on_error=1:detect_leaks=1:detect_stack_use_after_return=1"
      "LSAN_OPTIONS=suppressions='${WP_SAN_DIR}/lsan.supp'")
  endif()
  get_property(wp_tests DIRECTORY PROPERTY TESTS)
  set_tests_properties(${wp_tests} PROPERTIES ENVIRONMENT "${WP_SAN_ENV}")

  # Self-test: a deliberate bug per sanitizer must be reported and fail (expect_finding.cmake)
  add_executable(sanitizer_selftest tests/sanitizer/selftest.cpp)
  target_link_libraries(sanitizer_selftest PRIVATE Threads::Threads)
  set(wp_san_modes)
  if(WP_SANITIZE MATCHES "address")
    list(APPEND wp_san_modes "address|AddressSanitizer: heap-buffer-overflow")
  endif()
  if(WP_SANITIZE MATCHES "undefined")
    list(APPEND wp_san_modes "undefined|runtime error: signed integer overflow")
  endif()
  if(WP_SANITIZE MATCHES "thread")
    list(APPEND wp_san_modes "thread|ThreadSanitizer: data race")
  endif()
  foreach(entry IN LISTS wp_san_modes)
    string(REPLACE "|" ";" parts "${entry}")
    list(GET parts 0 mode)
    list(GET parts 1 pattern)
    add_test(NAME sanitizer_selftest_${mode}
      COMMAND ${CMAKE_COMMAND} -DBIN=$<TARGET_FILE:sanitizer_selftest> -DMODE=${mode}
        "-DPATTERN=${pattern}" -P ${WP_SAN_DIR}/expect_finding.cmake)
    set_tests_properties(sanitizer_selftest_${mode} PROPERTIES ENVIRONMENT "${WP_SAN_ENV}")
  endforeach()
endif()
