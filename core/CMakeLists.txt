cmake_minimum_required(VERSION 3.20)
project(wp_core LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Statische Teile landen in der geteilten Bibliothek wp_core (Linux, Android).
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Plattformen: macOS und iOS werden gebaut und getestet; Windows, Linux und Android sind konfiguriert
# (Bau dort in #13). iOS: cmake -S core -B core/build-ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS
# Android: cmake -S core -B core/build-android -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26
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

set(WP_THIRD_PARTY ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Wiedergabe-Logik ohne Audiogerät (für Tests und Offline-Rendering)
add_library(wp_engine STATIC src/engine.cpp src/metronome.cpp)
target_include_directories(wp_engine PUBLIC src
  ${WP_THIRD_PARTY}/signalsmith-stretch/include
  ${WP_THIRD_PARTY}/signalsmith-linear/include)

add_library(wp_miniaudio STATIC src/miniaudio_impl.c)
target_include_directories(wp_miniaudio PUBLIC ${WP_THIRD_PARTY}/miniaudio src)
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

# Tests
enable_testing()
add_executable(engine_tests tests/engine_tests.cpp)
target_link_libraries(engine_tests PRIVATE wp_engine Threads::Threads)
add_test(NAME engine_tests COMMAND engine_tests)

add_executable(metronome_tests tests/metronome_tests.cpp)
target_link_libraries(metronome_tests PRIVATE wp_engine)
add_test(NAME metronome_tests COMMAND metronome_tests)

add_executable(player_tests tests/player_tests.cpp)
target_link_libraries(player_tests PRIVATE wp_playercore)
target_include_directories(player_tests PRIVATE include)
target_compile_definitions(player_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
add_test(NAME player_tests COMMAND player_tests)
