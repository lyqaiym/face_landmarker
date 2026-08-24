cmake_minimum_required(VERSION 3.13)

# Pure-CMake stand-in for //mediapipe/framework/tool:encode_as_c_string.
# Cross-compiling for Android cannot run a target-built host tool, so the
# absl::CEscape + 79-column wrapping is reproduced here byte-for-byte.
#
# Usage: cmake -DINPUT=<binary> -DOUTPUT=<file.inc> -P encode_as_c_string.cmake

if(NOT DEFINED INPUT OR NOT DEFINED OUTPUT)
  message(FATAL_ERROR "usage: cmake -DINPUT=<file> -DOUTPUT=<file> -P encode_as_c_string.cmake")
endif()

file(READ "${INPUT}" hex HEX)
string(LENGTH "${hex}" hex_len)

set(out "\"")
set(line_len 1)
set(pos 0)

while(pos LESS hex_len)
  string(SUBSTRING "${hex}" ${pos} 2 pair)
  math(EXPR pos "${pos} + 2")
  math(EXPR d "0x${pair}")

  if(d EQUAL 10)
    set(esc "\\n")
  elseif(d EQUAL 13)
    set(esc "\\r")
  elseif(d EQUAL 9)
    set(esc "\\t")
  elseif(d EQUAL 34)
    set(esc "\\\"")
  elseif(d EQUAL 39)
    set(esc "\\'")
  elseif(d EQUAL 92)
    set(esc "\\\\")
  elseif(d GREATER_EQUAL 32 AND d LESS_EQUAL 126)
    string(ASCII ${d} esc)
  else()
    math(EXPR o1 "${d} / 64")
    math(EXPR o2 "(${d} / 8) % 8")
    math(EXPR o3 "${d} % 8")
    set(esc "\\${o1}${o2}${o3}")
  endif()

  string(LENGTH "${esc}" esc_len)
  math(EXPR next_len "${line_len} + ${esc_len}")
  if(next_len GREATER 79)
    string(APPEND out "\"\n\"")
    set(line_len 1)
  endif()
  string(APPEND out "${esc}")
  math(EXPR line_len "${line_len} + ${esc_len}")
endwhile()

string(APPEND out "\"\n")
file(WRITE "${OUTPUT}" "${out}")