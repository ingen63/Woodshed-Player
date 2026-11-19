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

# Kern mit C-API (wp_core.h)
if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(WP_RECORDER src/recorder_mac.mm)
else()
  set(WP_RECORDER src/recorder_stub.cpp)
endif()
add_library(wp_core SHARED src/player.cpp ${WP_RECORDER})
target_include_directories(wp_core PUBLIC include)
target_link_libraries(wp_core PRIVATE wp_playercore)
set_target_properties(wp_core PROPERTIES CXX_VISIBILITY_PRESET hidden)
wp_strict_warnings(wp_core)
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

# #9: audio reference cases against the offline C API, natively and under WASM (tests/reference.cmake)
include(tests/reference.cmake)

# #10: fuzz targets, replay of regression inputs and start corpus in every build
include(tests/fuzz/fuzz.cmake)

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
