# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

# Sets the minimum version of CMake required to build the native library.

cmake_minimum_required(VERSION 3.18.1)

# Declares and names the project.

project("LiteRT")
enable_language(ASM)
get_filename_component(MEDIAPIPEGESTURE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
message(STATUS "MEDIAPIPEGESTURE_ROOT=${MEDIAPIPEGESTURE_ROOT}")
set(GOOGLETEST_PATH ${MEDIAPIPEGESTURE_ROOT}/googletest/src/main/cpp/googletest)
set(GOOGLETEST_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/googletest)
set(GOOGLEBENCHMARK_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/benchmark)
# LiteRT's CMakeLists declares TFLITE_HOST_TOOLS_DIR and TENSORFLOW_SOURCE_DIR itself
# with `set(... CACHE PATH)`, which drops any same-named normal variable, so these have
# to go into the cache.
set(TENSORFLOW_SOURCE_DIR "${MEDIAPIPEGESTURE_ROOT}/tensorflow/src/main/cpp/tensorflow" CACHE PATH "TensorFlow source directory" FORCE)
#include_directories(${CMAKE_CURRENT_SOURCE_DIR}/LiteRT/src/main/cpp/LiteRT/tensor/internal)

set(TFLITE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/LiteRT/tflite")
set(CMAKE_MODULE_PATH
        "${TFLITE_SOURCE_DIR}/tools/cmake/modules"
        ${CMAKE_MODULE_PATH}
)
set(CMAKE_PREFIX_PATH
        "${TFLITE_SOURCE_DIR}/tools/cmake/modules"
        ${CMAKE_PREFIX_PATH}
)
list(APPEND CMAKE_MODULE_PATH "${TFLITE_SOURCE_DIR}/tflite/tools/cmake/modules")
message(STATUS "CMAKE_MODULE_PATH=${CMAKE_MODULE_PATH}")
#find_package(absl REQUIRED)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/abseil-cpp)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/third_party/abseil-cpp)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/cpuinfo)
set(CPUINFO_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/cpuinfo)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/eigen)
set(KLEIDIAI_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/kleidiai)
set(KLEIDIAI_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/kleidiai)
set(FXDIV_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/FXdiv)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/pthreadpool/include)
set(PTHREADPOOL_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/pthreadpool)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/pthreadpool)

# Both default to ON upstream, which pulls in XNNPACK's test/ and bench/ trees plus googletest
# and google-benchmark downloads. tflite's xnnpack.cmake normally turns them off, but the
# alias below makes that module return before it gets the chance.
set(XNNPACK_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(XNNPACK_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/XNNPACK)
# protobuf's install(EXPORT) lists libprotobuf-lite, which links absl targets. abseil-cpp
# defaults ABSL_ENABLE_INSTALL to OFF when it is not the top-level project, so those targets
# belong to no export set and the export generation fails. Nothing here is ever installed.
set(protobuf_INSTALL OFF CACHE BOOL "" FORCE)
# protobuf_BUILD_TESTS defaults ON, and cmake/tests.cmake builds upb-test against
# absl::scoped_mock_log. abseil marks that target TESTONLY, so it only exists when
# BUILD_TESTING and ABSL_BUILD_TESTING are both on -- neither is here. Nothing in this
# project runs protobuf's tests.
set(protobuf_BUILD_TESTS OFF CACHE BOOL "" FORCE)
#set(utf8_range_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/protobuf)
# XNNPACK/CMakeLists.txt names its library target "XNNPACK", but tflite's
# tools/cmake/modules/xnnpack.cmake short-circuits on the lower-case name. CMake target names
# are case-sensitive, so without this alias that module falls through and re-fetches XNNPACK
# from GitHub. The early return also skips the include_directories() that module normally
# publishes, so they are added here: xnnpack-delegate compiles against these headers without
# linking the XNNPACK target.
if(TARGET XNNPACK AND NOT TARGET xnnpack)
  add_library(xnnpack ALIAS XNNPACK)
endif()
include_directories(
        AFTER
        "${CMAKE_CURRENT_SOURCE_DIR}/XNNPACK/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/XNNPACK"
        "${CMAKE_CURRENT_SOURCE_DIR}/cpuinfo/include"
        "${PTHREADPOOL_SOURCE_DIR}/include"
)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/ruy)
# Upstream farmhash is an autotools project with no CMakeLists.txt. tflite ships a wrapper
# that compiles src/farmhash.cc directly; point it at the local checkout instead of letting
# farmhash.cmake fetch the pinned commit from GitHub.
set(FARMHASH_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/farmhash" CACHE PATH
        "Source directory for the CMake project." FORCE
)
add_subdirectory("${TFLITE_SOURCE_DIR}/tools/cmake/modules/farmhash")
message(WARNING "find_package farmhash")
find_package(farmhash REQUIRED)

set(FFT2D_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/OouraFFT-1.0" CACHE PATH
        "Source directory for the CMake project." FORCE
)
add_subdirectory("${TFLITE_SOURCE_DIR}/tools/cmake/modules/fft2d")
message(WARNING "find_package fft2d")
find_package(fft2d REQUIRED)

set(BUILD_TESTING OFF)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/gemmlowp/contrib)
if(NOT TARGET gemmlowp::gemmlowp)
  add_library(gemmlowp::gemmlowp ALIAS gemmlowp)
endif()
# Upstream ml_dtypes builds a numpy/Python extension module, which needs Python headers and
# is useless for Android. tflite only wants the header-only INTERFACE target, so use the
# wrapper it ships and point it at the local source.
#set(ML_DTYPES_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ml_dtypes" CACHE PATH "" FORCE)
#add_subdirectory(
#  ${CMAKE_CURRENT_SOURCE_DIR}/LiteRT/tflite/tools/cmake/modules/ml_dtypes
#  ${CMAKE_BINARY_DIR}/ml_dtypes-build
#)
set(ML_DTYPES_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ml_dtypes" CACHE PATH
        "Source directory for the CMake project." FORCE
)
add_subdirectory("${TFLITE_SOURCE_DIR}/tools/cmake/modules/ml_dtypes")
#message(WARNING "find_package ml_dtypes")
#find_package(ml_dtypes REQUIRED)
# tflite links flatbuffers::flatbuffers, but its FindFlatBuffers.cmake only creates that
# alias on the FetchContent path, which short-circuits because the target already exists here.
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/flatbuffers)
message(WARNING "find_package flatbuffers")
if(NOT TARGET flatbuffers::flatbuffers)
  add_library(flatbuffers::flatbuffers ALIAS flatbuffers)
endif()
find_package(flatbuffers REQUIRED)
message(WARNING "find_package FP16")
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/FP16)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/FP16/include)
message(WARNING "find_package tflite1")
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/LiteRT/tflite)
message(WARNING "find_package tflite2")
add_library(temp SHARED source.cpp)
target_link_libraries(temp PUBLIC
        farmhash
        ml_dtypes
        fft2d_alloc
        fft2d_fftsg2d)