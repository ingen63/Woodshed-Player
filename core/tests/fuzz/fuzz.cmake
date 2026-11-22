# #10/AK4: fuzz targets of the core (tests/fuzz/, docs/TESTS.md). Included from CMakeLists.txt after
# tests/reference.cmake (fuzz_capi drives wp_core_offline).
#
# Every build has a replay test per target (fuzz_<target>_replay): it runs the checked-in
# regression inputs first, then the start corpus, without libFuzzer, so they also run in Release,
# Debug and the sanitizer builds (#57). With WP_FUZZ=ON (make fuzz, clang with libFuzzer, e.g.
# Homebrew llvm) the build also has the libFuzzer programs fuzz_<target>; all code of that build is
# instrumented for coverage (-fsanitize=fuzzer-no-link), the programs link libFuzzer. Together with
# WP_SANITIZE=address,undefined every finding (crash, sanitizer, broken invariant) ends the run.
set(WP_FUZZ_DIR ${CMAKE_CURRENT_SOURCE_DIR}/tests/fuzz)
set(wp_fuzz_libs_decoder wp_playercore)
set(wp_fuzz_libs_capi wp_core_offline)
set(wp_fuzz_libs_trim wp_trim) # #116
foreach(name decoder capi trim)
  set(src ${WP_FUZZ_DIR}/fuzz_${name}.cpp)
  add_executable(fuzz_${name}_replay ${src} ${WP_FUZZ_DIR}/replay_main.cpp)
  target_link_libraries(fuzz_${name}_replay PRIVATE ${wp_fuzz_libs_${name}})
  wp_strict_warnings(fuzz_${name}_replay)
  add_test(NAME fuzz_${name}_replay
    COMMAND fuzz_${name}_replay ${WP_FUZZ_DIR}/regressions/${name} ${WP_FUZZ_DIR}/corpus/${name})
  if(WP_FUZZ)
    add_executable(fuzz_${name} ${src})
    target_link_libraries(fuzz_${name} PRIVATE ${wp_fuzz_libs_${name}})
    target_compile_options(fuzz_${name} PRIVATE -fsanitize=fuzzer)
    target_link_options(fuzz_${name} PRIVATE -fsanitize=fuzzer)
    wp_strict_warnings(fuzz_${name})
  endif()
endforeach()
# #86/AK1, AK2: the checked-in capi inputs together reach every C API function fuzz_capi calls (read from its
# source, see replay_main.cpp); the test names each function no input reaches.
add_test(NAME fuzz_capi_reached
  COMMAND fuzz_capi_replay --reached ${WP_FUZZ_DIR}/fuzz_capi.cpp ${WP_FUZZ_DIR}/regressions/capi
    ${WP_FUZZ_DIR}/corpus/capi)
