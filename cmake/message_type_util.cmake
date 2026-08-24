cmake_minimum_required(VERSION 3.13)

# Pure-CMake stand-in for //mediapipe/framework/tool:message_type_util, which cannot run
# here: it is a target-built C++ binary and we are cross-compiling for Android.
#
# The tool reads a *direct* FileDescriptorSet and writes two macros. For a single
# proto_library that set holds exactly one file, so reading the .proto text gives the same
# answer as parsing the descriptor. The type it picks is the top-level message whose
# lowercased name shares the longest prefix with the .proto basename minus underscores
# (DescriptorReader::BestTypeName); ties go to the first in sorted order, matching the
# std::set the tool iterates.
#
# Usage: cmake -DPROTO=<file.proto> -DOUTPUT=<type_name.h> -P message_type_util.cmake

if(NOT DEFINED PROTO OR NOT DEFINED OUTPUT)
  message(FATAL_ERROR "usage: cmake -DPROTO=<f> -DOUTPUT=<f> -P message_type_util.cmake")
endif()

file(STRINGS "${PROTO}" lines)

set(package "")
set(messages "")
set(depth 0)

foreach(line IN LISTS lines)
  string(REGEX REPLACE "//.*$" "" code "${line}")

  if(depth EQUAL 0 AND code MATCHES "^[ \t]*package[ \t]+([A-Za-z0-9_.]+)[ \t]*;")
    set(package "${CMAKE_MATCH_1}")
  endif()

  if(depth EQUAL 0 AND code MATCHES "^[ \t]*message[ \t]+([A-Za-z0-9_]+)")
    list(APPEND messages "${CMAKE_MATCH_1}")
  endif()

  string(REGEX MATCHALL "{" opens "${code}")
  string(REGEX MATCHALL "}" closes "${code}")
  list(LENGTH opens n_open)
  list(LENGTH closes n_close)
  math(EXPR depth "${depth} + ${n_open} - ${n_close}")
endforeach()

if(NOT messages)
  message(FATAL_ERROR "no top-level message found in ${PROTO}")
endif()

get_filename_component(stem "${PROTO}" NAME_WE)
string(REPLACE "_" "" stem "${stem}")
string(TOLOWER "${stem}" stem)
string(LENGTH "${stem}" stem_len)

list(SORT messages)

set(best_name "")
set(best_match -1)
foreach(msg IN LISTS messages)
  string(TOLOWER "${msg}" lower)
  string(LENGTH "${lower}" lower_len)
  set(limit ${stem_len})
  if(lower_len LESS limit)
    set(limit ${lower_len})
  endif()
  set(match 0)
  while(match LESS limit)
    string(SUBSTRING "${stem}" ${match} 1 a)
    string(SUBSTRING "${lower}" ${match} 1 b)
    if(NOT a STREQUAL b)
      break()
    endif()
    math(EXPR match "${match} + 1")
  endwhile()
  if(match GREATER best_match)
    set(best_match ${match})
    set(best_name "${msg}")
  endif()
endforeach()

string(REPLACE "." "::" ns "${package}")

file(WRITE "${OUTPUT}"
  "#define MP_OPTION_TYPE_NS ${ns}\n#define MP_OPTION_TYPE_NAME ${best_name}\n")
