cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "files_channel.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
# #140, #60: the program starts the app again under its own name (main.cc)
add_definitions(-DBINARY_NAME="${BINARY_NAME}")

# #50/AK6: Git tag and build date for the About dialog, fixed when the build is configured
execute_process(COMMAND git describe --tags --abbrev=0
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" OUTPUT_VARIABLE WP_GIT_TAG
  OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
string(TIMESTAMP WP_BUILD_DATE "%Y-%m-%d" UTC)
add_definitions(-DWP_GIT_TAG="${WP_GIT_TAG}" -DWP_BUILD_DATE="${WP_BUILD_DATE}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK ${CMAKE_DL_LIBS})

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
