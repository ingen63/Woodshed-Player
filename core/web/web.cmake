# Emscripten-Zweig (#33), eingebunden aus core/CMakeLists.txt.
# Zwei Varianten derselben Quellen:
#  - Tests mit Threads (-pthread) unter Node.js, damit dieselben ctest-Fälle wie nativ laufen
#    (Tempo, Loop-Grenzen, Seek, Laden). Node.js führt sie über CMAKE_CROSSCOMPILING_EMULATOR aus.
#  - wp_core_web.wasm ohne Threads und ohne JS-Hülle (STANDALONE_WASM) fürs AudioWorklet.
set(WP_ENGINE_SOURCES src/engine.cpp src/metronome.cpp src/waveform.cpp)
set(WP_ENGINE_INCLUDES src)
set(WP_ENGINE_SYSTEM_INCLUDES ${WP_THIRD_PARTY}/signalsmith-stretch/include ${WP_THIRD_PARTY}/signalsmith-linear/include)
# Im Browser nur Dekodieren: kein Audiogerät (das ist das AudioWorklet), keine Threads in miniaudio.
set(WP_MINIAUDIO_DEFS MA_NO_DEVICE_IO MA_NO_THREADING)

# Native WASM exceptions: without them Emscripten turns every throw (std::bad_alloc when memory runs
# out) into abort(), and the catch branches of the core (WP_ERR_OUT_OF_MEMORY, fallbacks) never run.
# Supported by all browsers the web app targets (Chrome 95, Firefox 100, Safari 15.2) and Node.js.
set(WP_WASM_EXCEPTIONS -fwasm-exceptions)

# ---- Tests unter Node.js ----
set(WP_TEST_COMPILE -pthread -msimd128 ${WP_WASM_EXCEPTIONS})
set(WP_TEST_LINK ${WP_WASM_EXCEPTIONS} -pthread -sPROXY_TO_PTHREAD -sEXIT_RUNTIME=1 -sNODERAWFS=1 -sALLOW_MEMORY_GROWTH=1
  -sINITIAL_MEMORY=128MB -sMAXIMUM_MEMORY=2GB -sSTACK_SIZE=1MB -sPTHREAD_POOL_SIZE=8 -Wno-pthreads-mem-growth)

add_library(wp_engine STATIC ${WP_ENGINE_SOURCES})
target_include_directories(wp_engine PUBLIC ${WP_ENGINE_INCLUDES})
target_include_directories(wp_engine SYSTEM PUBLIC ${WP_ENGINE_SYSTEM_INCLUDES})
wp_strict_warnings(wp_engine)
target_compile_options(wp_engine PUBLIC ${WP_TEST_COMPILE})
target_link_options(wp_engine PUBLIC ${WP_TEST_LINK})

add_library(wp_miniaudio STATIC src/miniaudio_impl.c)
target_include_directories(wp_miniaudio SYSTEM PUBLIC ${WP_THIRD_PARTY}/miniaudio)
target_include_directories(wp_miniaudio PUBLIC src)
target_compile_definitions(wp_miniaudio PUBLIC MA_NO_DEVICE_IO)
target_compile_options(wp_miniaudio PUBLIC ${WP_TEST_COMPILE})

add_library(wp_playercore STATIC src/player_core.cpp)
target_link_libraries(wp_playercore PUBLIC wp_engine wp_miniaudio)
wp_strict_warnings(wp_playercore)

# #116: libFLAC (FLAC encoded again when trimming), the FLAC writer and the trimming itself, as natively
set(WP_FLAC_DEFS FLAC__NO_DLL HAVE_CONFIG_H)
set(WP_FLAC_INCLUDES ${WP_FLAC}/include ${CMAKE_CURRENT_SOURCE_DIR}/src/flac_config
  ${WP_FLAC}/src/libFLAC/include)
add_library(wp_flac STATIC ${WP_FLAC_SOURCES})
target_compile_definitions(wp_flac PRIVATE ${WP_FLAC_DEFS})
target_include_directories(wp_flac SYSTEM PUBLIC ${WP_FLAC_INCLUDES})
target_compile_options(wp_flac PRIVATE ${WP_TEST_COMPILE})
add_library(wp_flacwriter STATIC src/flac_writer.cpp)
target_include_directories(wp_flacwriter PUBLIC src)
target_link_libraries(wp_flacwriter PUBLIC wp_flac)
wp_strict_warnings(wp_flacwriter)
target_compile_options(wp_flacwriter PUBLIC ${WP_TEST_COMPILE})
add_library(wp_trim STATIC src/trim.cpp src/trim_mp4.cpp)
target_include_directories(wp_trim PUBLIC include src)
target_link_libraries(wp_trim PUBLIC wp_miniaudio wp_flacwriter)
target_link_options(wp_trim PUBLIC ${WP_TEST_LINK})
wp_strict_warnings(wp_trim)

enable_testing()
foreach(t engine metronome waveform)
  add_executable(${t}_tests tests/${t}_tests.cpp)
  target_link_libraries(${t}_tests PRIVATE wp_engine)
  wp_strict_warnings(${t}_tests)
  add_test(NAME ${t}_tests COMMAND ${t}_tests)
endforeach()
add_executable(player_tests tests/player_tests.cpp)
target_link_libraries(player_tests PRIVATE wp_playercore)
target_include_directories(player_tests PRIVATE include)
target_compile_definitions(player_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(player_tests)
add_test(NAME player_tests COMMAND player_tests)
add_executable(trim_tests tests/trim_tests.cpp src/trim_api.cpp)
target_link_libraries(trim_tests PRIVATE wp_trim wp_playercore)
target_compile_definitions(trim_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(trim_tests)
add_test(NAME trim_tests COMMAND trim_tests)
add_executable(trim_mp4_tests tests/trim_mp4_tests.cpp src/trim_api.cpp) # #120
target_link_libraries(trim_mp4_tests PRIVATE wp_trim)
target_compile_definitions(trim_mp4_tests PRIVATE WP_TEST_AUDIO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/audio")
wp_strict_warnings(trim_mp4_tests)
add_test(NAME trim_mp4_tests COMMAND trim_mp4_tests)

# #9: the same reference cases as natively; compared against the native outputs (#9/AK7)
include(tests/reference.cmake)

# #67: replay of the fuzz regressions and start corpus (tests/fuzz/fuzz.cmake) against the WASM build
# under Node.js; checked-in findings in tests/fuzz/regressions/<target> come along automatically.
include(tests/fuzz/fuzz.cmake)

# ---- Kern fürs AudioWorklet ----
# #116: trimming (src/trim*.cpp, the FLAC writer and libFLAC) is part of the web core.
set(WP_WEB_OWN web/wp_core_web.cpp src/recorder_stub.cpp src/player_core.cpp src/trim.cpp src/trim_mp4.cpp
  src/trim_api.cpp src/mp3_api_stub.cpp src/flac_writer.cpp ${WP_ENGINE_SOURCES})
add_executable(wp_core_web ${WP_WEB_OWN} src/miniaudio_impl.c ${WP_FLAC_SOURCES})
target_include_directories(wp_core_web PRIVATE include web ${WP_ENGINE_INCLUDES})
target_include_directories(wp_core_web SYSTEM PRIVATE ${WP_ENGINE_SYSTEM_INCLUDES} ${WP_THIRD_PARTY}/miniaudio
  ${WP_FLAC_INCLUDES})
# #7: strict warnings for our own sources only, not for miniaudio_impl.c (compiles miniaudio itself)
# and libFLAC.
if(WP_STRICT_WARNINGS)
  set_source_files_properties(${WP_WEB_OWN}
    TARGET_DIRECTORY wp_core_web PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra;-Werror")
endif()
set_source_files_properties(${WP_FLAC_SOURCES} TARGET_DIRECTORY wp_core_web PROPERTIES
  COMPILE_DEFINITIONS "${WP_FLAC_DEFS}")
target_compile_definitions(wp_core_web PRIVATE ${WP_MINIAUDIO_DEFS})
target_compile_options(wp_core_web PRIVATE -msimd128 -O3 ${WP_WASM_EXCEPTIONS})
target_link_options(wp_core_web PRIVATE -O3 ${WP_WASM_EXCEPTIONS} -sSTANDALONE_WASM --no-entry -sFILESYSTEM=0
  -sINITIAL_MEMORY=64MB -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=2GB -sSTACK_SIZE=256KB)
set_target_properties(wp_core_web PROPERTIES SUFFIX ".wasm")

# Der WASM-Kern selbst: Dekodieren (MP3, WAV, FLAC), PCM aus dem Browser (AAC/M4A), Tempo, Loop, Seek.
find_program(NODE_EXECUTABLE node)
add_test(NAME wp_core_web_tests
  COMMAND ${NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/web/wp_core_web_test.mjs
          $<TARGET_FILE:wp_core_web> ${CMAKE_CURRENT_SOURCE_DIR}/tests/audio)
