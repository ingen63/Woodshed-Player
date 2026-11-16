cmake_minimum_required(VERSION 3.20)
project(wp_core LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(APPLE)
  enable_language(OBJCXX)
  set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0 CACHE STRING "")
endif()

set(WP_THIRD_PARTY ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Wiedergabe-Logik ohne Audiogerät (für Tests und Offline-Rendering)
add_library(wp_engine STATIC src/engine.cpp src/metronome.cpp)
target_include_directories(wp_engine PUBLIC src
  ${WP_THIRD_PARTY}/signalsmith-stretch/include
  ${WP_THIRD_PARTY}/signalsmith-linear/include)

add_library(wp_miniaudio STATIC src/miniaudio_impl.c)
target_include_directories(wp_miniaudio PUBLIC ${WP_THIRD_PARTY}/miniaudio src)
if(APPLE)
  target_link_libraries(wp_miniaudio PUBLIC "-framework CoreFoundation" "-framework CoreAudio" "-framework AudioToolbox")
elseif(UNIX)
  target_link_libraries(wp_miniaudio PUBLIC dl pthread m)
endif()

# Kern mit C-API (wp_core.h)
if(APPLE AND NOT IOS)
  set(WP_RECORDER src/recorder_mac.mm)
else()
  set(WP_RECORDER src/recorder_stub.cpp)
endif()
add_library(wp_core SHARED src/player.cpp ${WP_RECORDER})
target_include_directories(wp_core PUBLIC include)
target_link_libraries(wp_core PRIVATE wp_engine wp_miniaudio)
set_target_properties(wp_core PROPERTIES CXX_VISIBILITY_PRESET hidden)
if(APPLE)
  target_compile_options(wp_core PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
  target_link_libraries(wp_core PRIVATE "-framework Foundation")
endif()

# Werkzeug: Datei offline mit Tempo rendern (Hörvergleich)
add_executable(wp_render tools/wp_render.cpp)
target_link_libraries(wp_render PRIVATE wp_engine wp_miniaudio)

# Tests
enable_testing()
add_executable(engine_tests tests/engine_tests.cpp)
target_link_libraries(engine_tests PRIVATE wp_engine)
add_test(NAME engine_tests COMMAND engine_tests)

add_executable(metronome_tests tests/metronome_tests.cpp)
target_link_libraries(metronome_tests PRIVATE wp_engine)
add_test(NAME metronome_tests COMMAND metronome_tests)
