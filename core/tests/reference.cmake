# #9: audio reference cases (tests/reference_tests.cpp), included from CMakeLists.txt (native) and
# web/web.cmake (WebAssembly under Node.js) after wp_playercore exists.
#
# wp_core_offline is the C API of wp_core.h without an audio device: web/wp_core_web.cpp (the same
# source as the browser core) with file loading (WP_WEB_FILES) and src/recorder_stub.cpp. The
# native run writes every recorded output to reference_native.bin in its build folder; the WASM
# run compares against core/build/reference_native.bin (WP_REFERENCE_DUMP), tolerance 1e-6
# (#9/AK7). reference_api_coverage fails if a WP_API function of wp_core.h has no reference case.
add_library(wp_core_offline STATIC web/wp_core_web.cpp src/recorder_stub.cpp)
target_include_directories(wp_core_offline PUBLIC include web)
target_compile_definitions(wp_core_offline PUBLIC WP_WEB_FILES)
target_link_libraries(wp_core_offline PUBLIC wp_playercore)
wp_strict_warnings(wp_core_offline)

add_executable(reference_tests tests/reference_tests.cpp)
target_link_libraries(reference_tests PRIVATE wp_core_offline)
target_compile_definitions(reference_tests PRIVATE
  WP_GOLDEN_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/golden"
  WP_TEST_TMP_DIR="${CMAKE_CURRENT_BINARY_DIR}")
wp_strict_warnings(reference_tests)

if(EMSCRIPTEN)
  set(WP_REFERENCE_DUMP "${CMAKE_CURRENT_SOURCE_DIR}/build/reference_native.bin" CACHE FILEPATH
    "Outputs of the native reference_tests run (make test-core) that the WASM run compares against")
  add_test(NAME reference_tests COMMAND reference_tests --compare ${WP_REFERENCE_DUMP})
else()
  add_test(NAME reference_tests
    COMMAND reference_tests --dump ${CMAKE_CURRENT_BINARY_DIR}/reference_native.bin)
endif()

add_test(NAME reference_api_coverage
  COMMAND ${CMAKE_COMMAND} -DHEADER=${CMAKE_CURRENT_SOURCE_DIR}/include/wp_core.h
    -DCASES=${CMAKE_CURRENT_SOURCE_DIR}/tests/reference_tests.cpp
    -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/reference_api_coverage.cmake)
