# #60: the audio core (core/) as the library of the Flutter plugin on Windows and Linux. Built from
# the sources in core/src like the podspecs of macOS and iOS, without tests and tools; the core's
# own build with its tests is core/CMakeLists.txt. Windows: wp_core.dll (miniaudio plays through
# WASAPI), Linux: libwp_core.so (PulseAudio or ALSA, loaded by miniaudio at run time). No recording
# (#162) and no MP3 export there: the C API answers with the stubs.
cmake_minimum_required(VERSION 3.14)
project(wp_core_library LANGUAGES C CXX)

# The plugin folder is reached through a link (flutter/ephemeral/.plugin_symlinks); the core lies
# next to the app, relative to the real folder.
get_filename_component(WP_PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)
get_filename_component(WP_CORE_DIR "${WP_PLUGIN_DIR}/../../../core" ABSOLUTE)
set(WP_SRC "${WP_CORE_DIR}/src")
set(WP_TP "${WP_CORE_DIR}/third_party")
set(WP_FLAC "${WP_TP}/flac/src/libFLAC")

add_library(wp_flac_plugin STATIC
  ${WP_FLAC}/bitmath.c ${WP_FLAC}/bitreader.c ${WP_FLAC}/bitwriter.c ${WP_FLAC}/cpu.c
  ${WP_FLAC}/crc.c ${WP_FLAC}/fixed.c ${WP_FLAC}/float.c ${WP_FLAC}/format.c ${WP_FLAC}/lpc.c
  ${WP_FLAC}/md5.c ${WP_FLAC}/memory.c ${WP_FLAC}/stream_decoder.c ${WP_FLAC}/stream_encoder.c
  ${WP_FLAC}/stream_encoder_framing.c ${WP_FLAC}/window.c)
if(WIN32)
  target_sources(wp_flac_plugin PRIVATE ${WP_TP}/flac/src/share/win_utf8_io/win_utf8_io.c)
endif()
target_compile_definitions(wp_flac_plugin PUBLIC FLAC__NO_DLL PRIVATE HAVE_CONFIG_H)
target_include_directories(wp_flac_plugin SYSTEM PUBLIC ${WP_TP}/flac/include)
target_include_directories(wp_flac_plugin SYSTEM PRIVATE ${WP_SRC}/flac_config
  ${WP_FLAC}/include)
set_target_properties(wp_flac_plugin PROPERTIES POSITION_INDEPENDENT_CODE ON
  C_VISIBILITY_PRESET hidden)

set(WP_CORE_SOURCES
  ${WP_SRC}/player.cpp ${WP_SRC}/player_core.cpp ${WP_SRC}/engine.cpp ${WP_SRC}/metronome.cpp
  ${WP_SRC}/waveform.cpp ${WP_SRC}/miniaudio_impl.c ${WP_SRC}/trim.cpp ${WP_SRC}/trim_mp4.cpp
  ${WP_SRC}/trim_api.cpp ${WP_SRC}/flac_writer.cpp ${WP_SRC}/mp3_api_stub.cpp
  ${WP_SRC}/recorder_stub.cpp)
if(NOT WIN32)
  # #140: the command line of the app's program (wp_cli_main), loaded by the Linux runner. Windows
  # has its own console program for it (app/windows/runner).
  list(APPEND WP_CORE_SOURCES ${WP_SRC}/cli.cpp ${WP_SRC}/cli_posix.cpp)
endif()
add_library(wp_core SHARED ${WP_CORE_SOURCES})
set_target_properties(wp_core PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON
  CXX_VISIBILITY_PRESET hidden C_VISIBILITY_PRESET hidden POSITION_INDEPENDENT_CODE ON)
target_include_directories(wp_core PRIVATE ${WP_CORE_DIR}/include ${WP_SRC})
target_include_directories(wp_core SYSTEM PRIVATE ${WP_TP}/miniaudio
  ${WP_TP}/signalsmith-stretch/include ${WP_TP}/signalsmith-linear/include)
target_link_libraries(wp_core PRIVATE wp_flac_plugin)
target_compile_definitions(wp_core PRIVATE DART_SHARED_LIB)
if(MSVC)
  target_compile_options(wp_core PRIVATE /utf-8 /EHsc)
  target_compile_definitions(wp_core PRIVATE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(wp_flac_plugin PRIVATE /utf-8)
  target_compile_definitions(wp_flac_plugin PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
  # #9/AK7: no fused multiply-add, the same samples as the web core and the tests
  target_compile_options(wp_core PRIVATE -ffp-contract=off)
  find_package(Threads REQUIRED)
  target_link_libraries(wp_core PRIVATE Threads::Threads ${CMAKE_DL_LIBS} m)
  target_link_libraries(wp_flac_plugin PRIVATE m)
endif()
