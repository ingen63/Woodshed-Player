# Runs the sanitizer self-test in one mode and requires a report and a non-zero exit code (#57).
# cmake -DBIN=<sanitizer_selftest> -DMODE=address|undefined|thread -DPATTERN=<regex> -P <this file>
execute_process(COMMAND "${BIN}" "${MODE}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(rc EQUAL 0)
  message(FATAL_ERROR "sanitizer mode ${MODE}: the deliberate bug ended with exit code 0\n${out}${err}")
endif()
if(NOT "${out}${err}" MATCHES "${PATTERN}")
  message(FATAL_ERROR "sanitizer mode ${MODE}: no report matching '${PATTERN}' (exit ${rc})\n${out}${err}")
endif()
message(STATUS "sanitizer mode ${MODE}: finding reported, exit code ${rc}")
