cmake_minimum_required(VERSION 3.13)

# Stand-in for Bazel's expand_template rule: literal string substitution, no CMake
# @VAR@ semantics, so templates using {{PLACEHOLDER}} pass through untouched except for
# the keys given here.
#
# Usage: cmake -DTEMPLATE=<in> -DOUTPUT=<out> -DSUBS="k1=v1;k2=v2" -P expand_template.cmake

if(NOT DEFINED TEMPLATE OR NOT DEFINED OUTPUT OR NOT DEFINED SUBS)
  message(FATAL_ERROR
    "usage: cmake -DTEMPLATE=<f> -DOUTPUT=<f> -DSUBS=\"k=v;...\" -P expand_template.cmake")
endif()

file(READ "${TEMPLATE}" text)

foreach(sub IN LISTS SUBS)
  string(FIND "${sub}" "=" pos)
  if(pos LESS 0)
    message(FATAL_ERROR "substitution is not key=value: ${sub}")
  endif()
  string(SUBSTRING "${sub}" 0 ${pos} key)
  math(EXPR after "${pos} + 1")
  string(SUBSTRING "${sub}" ${after} -1 value)
  string(REPLACE "${key}" "${value}" text "${text}")
endforeach()

file(WRITE "${OUTPUT}" "${text}")
