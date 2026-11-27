cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# #140, #60: the command line of the core (core/src/cli.cpp) with its Windows transport, for the
# console program WoodshedPlayer.com. The core's sources keep their own warning level.
get_filename_component(WP_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../core" ABSOLUTE)
add_library(wp_cli_win STATIC "${WP_CORE_DIR}/src/cli.cpp" "${WP_CORE_DIR}/src/cli_win.cpp")
target_include_directories(wp_cli_win PUBLIC "${WP_CORE_DIR}/include" "${WP_CORE_DIR}/src")
target_compile_features(wp_cli_win PUBLIC cxx_std_17)
target_compile_options(wp_cli_win PRIVATE /utf-8 /EHsc)
target_link_libraries(wp_cli_win PUBLIC ws2_32)

# #50/AK6: Git tag and build date for the About dialog, fixed when the build is configured
execute_process(COMMAND git describe --tags --abbrev=0
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" OUTPUT_VARIABLE WP_GIT_TAG
  OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
string(TIMESTAMP WP_BUILD_DATE "%Y-%m-%d" UTC)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "command_bridge.cpp"
  "command_line.cpp"
  "files_channel.cpp"
  "flutter_window.cpp"
  "keychain_channel.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" wp_cli_win ole32 shell32 advapi32)
target_compile_definitions(${BINARY_NAME} PRIVATE "WP_GIT_TAG=\"${WP_GIT_TAG}\""
  "WP_BUILD_DATE=\"${WP_BUILD_DATE}\"")
target_include_directories(${BINARY_NAME} PRIVATE "${WP_CORE_DIR}/include")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# #140, #60: WoodshedPlayer.com next to WoodshedPlayer.exe. cmd and PowerShell take .com before .exe,
# so «WoodshedPlayer play ...» runs the console program, which the shell waits for.
add_executable(WoodshedPlayerCommand "cli_main.cpp" "command_line.cpp")
apply_standard_settings(WoodshedPlayerCommand)
target_compile_definitions(WoodshedPlayerCommand PRIVATE "NOMINMAX" "UNICODE" "_UNICODE")
target_link_libraries(WoodshedPlayerCommand PRIVATE wp_cli_win ole32 shell32)
set_target_properties(WoodshedPlayerCommand PROPERTIES OUTPUT_NAME "WoodshedPlayer" SUFFIX ".com")
