# #60: the audio core for the Windows app (wp_core.dll next to the program).
cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "wp_core")
project(${PROJECT_NAME} LANGUAGES C CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(wp_core_bundled_libraries
  $<TARGET_FILE:wp_core>
  PARENT_SCOPE
)
