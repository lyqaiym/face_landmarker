cmake_minimum_required(VERSION 3.18)

# protoc and flatc must run on the build host while everything else cross-compiles for
# Android, so they are built as separate CMake projects with no toolchain file.
#
# Both come from the vendored sources rather than PATH: generated .pb.cc files assert
# against the protobuf runtime version, and the vendored runtime is 6.31.1, so a newer
# protoc would emit code that refuses to compile against it.
#
# This happens at configure time, not via ExternalProject, because LiteRT's CMakeLists
# checks TFLITE_HOST_TOOLS_DIR for flatc while configuring and fails outright if it is
# missing. Each build is skipped once its binary exists, so reconfigures are cheap.
#
# Defines MP_PROTOC, MP_FLATC and MP_HOST_TOOLS_DIR.

set(_host "${CMAKE_BINARY_DIR}/host")
set(MP_PROTOC "${_host}/protoc-build/protoc")
set(MP_FLATC "${_host}/flatc-build/flatc")
set(MP_HOST_TOOLS_DIR "${_host}/flatc-build")

# enable_language(CXX) under the NDK toolchain exports CC and CXX into the environment,
# which every execute_process child inherits. A sub-build that picks those up compiles
# with the cross compiler against the host SDK's libc++ and fails, so the host compiler
# is pinned instead. NO_DEFAULT_PATH because find_program is rerooted into the NDK
# sysroot here and would otherwise find nothing, or find the wrong thing.
find_program(MP_HOST_CC NAMES cc clang gcc
  PATHS /usr/bin /usr/local/bin /opt/homebrew/bin NO_DEFAULT_PATH REQUIRED)
find_program(MP_HOST_CXX NAMES c++ clang++ g++
  PATHS /usr/bin /usr/local/bin /opt/homebrew/bin NO_DEFAULT_PATH REQUIRED)

function(_mp_build_host_tool name binary source_dir binary_dir)
  if(EXISTS "${binary}")
    return()
  endif()
  message(STATUS "building host ${name} (once)")
  execute_process(
    COMMAND ${CMAKE_COMMAND} -S "${source_dir}" -B "${binary_dir}" -G "${CMAKE_GENERATOR}"
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_C_COMPILER=${MP_HOST_CC}
            -DCMAKE_CXX_COMPILER=${MP_HOST_CXX}
            ${ARGN}
    RESULT_VARIABLE res OUTPUT_VARIABLE log ERROR_VARIABLE log)
  if(NOT res EQUAL 0)
    message(FATAL_ERROR "configuring host ${name} failed:\n${log}")
  endif()
  execute_process(
    COMMAND ${CMAKE_COMMAND} --build "${binary_dir}" --target ${name}
    RESULT_VARIABLE res OUTPUT_VARIABLE log ERROR_VARIABLE log)
  if(NOT res EQUAL 0)
    message(FATAL_ERROR "building host ${name} failed:\n${log}")
  endif()
  if(NOT EXISTS "${binary}")
    message(FATAL_ERROR "host ${name} built but ${binary} is missing")
  endif()
endfunction()

_mp_build_host_tool(flatc "${MP_FLATC}"
  "${MP_ROOT}/LiteRT/src/main/cpp/flatbuffers" "${_host}/flatc-build"
  -DFLATBUFFERS_BUILD_FLATC=ON
  -DFLATBUFFERS_BUILD_FLATLIB=OFF
  -DFLATBUFFERS_BUILD_FLATHASH=OFF
  -DFLATBUFFERS_BUILD_TESTS=OFF
  -DFLATBUFFERS_INSTALL=OFF
)

_mp_build_host_tool(protoc "${MP_PROTOC}"
  "${MP_ROOT}/LiteRT/src/main/cpp/protobuf" "${_host}/protoc-build"
  -DCMAKE_CXX_STANDARD=17
  -Dprotobuf_BUILD_TESTS=OFF
  -Dprotobuf_INSTALL=OFF
  -Dprotobuf_BUILD_PROTOC_BINARIES=ON
  # Keeps upb's checked-in bootstrap headers (upb/reflection/cmake) on the include path;
  # with LIBUPB off, libprotoc fails on a missing descriptor.upb.h.
  -Dprotobuf_BUILD_LIBUPB=ON
  # Resolve abseil from the checkout instead of fetching it, so this works offline and
  # against the same abseil the target build links.
  -Dprotobuf_FORCE_FETCH_DEPENDENCIES=ON
  -DFETCHCONTENT_SOURCE_DIR_ABSL=${MP_ROOT}/LiteRT/src/main/cpp/abseil-cpp
  -DABSL_PROPAGATE_CXX_STD=ON
)
