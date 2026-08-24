# libmediapipe_tasks_jni.so
#
# Everything under generated/ is produced by tools/bazel2cmake from `bazel aquery` output
# and must not be hand-edited; run tools/bazel2cmake/regen.sh instead. This file holds
# only what cannot be derived from the Bazel graph: where the dependency layer lives and
# what its CMake target names are.

cmake_minimum_required(VERSION 3.18.1)
project(mediapipe_tasks_jni CXX C ASM)

set(MP_MODULE "${CMAKE_CURRENT_SOURCE_DIR}")
get_filename_component(MP_ROOT "${MP_MODULE}/../../../.." ABSOLUTE)
set(MP_SRC "${MP_ROOT}/mediapipesource")          # the Bazel workspace root
set(MP_GEN "${CMAKE_CURRENT_BINARY_DIR}/gen")     # output of our own codegen rules

message(STATUS "MP_GEN=${MP_GEN}")
# mediapipe/util/cpu_util.cc includes "ndk/sources/android/cpufeatures/cpu-features.h",
# which Bazel resolves against @androidndk's repo root -- a tree with the whole NDK under
# an `ndk/` subdirectory. Recreate just that one level of nesting so the same
# quote-include, and the cpufeatures object library the generator emits, both resolve.
set(MP_NDK "${CMAKE_CURRENT_BINARY_DIR}/ndkroot")
file(MAKE_DIRECTORY "${MP_NDK}")
file(CREATE_LINK "${ANDROID_NDK}" "${MP_NDK}/ndk" SYMBOLIC)

# protoc and flatc, built for the host. Defines MP_PROTOC, MP_FLATC, MP_HOST_TOOLS_DIR.
include("${MP_ROOT}/cmake/host_tools.cmake")

# Bazel hands the linker loose objects and produces exactly one .so, so every dependency
# here is static. This has to be decided before the first add_subdirectory: glog's
# CMakeLists does `option(BUILD_SHARED_LIBS ... ON)`, which writes the cache. glog is added
# after LiteRT, so a fresh build dir configured abseil and tflite static while any later
# reconfigure of the same dir picked up the cached ON and rebuilt them as 90-odd shared
# libraries. option() leaves an existing cache entry alone, so seeding it settles both.
# FORCE, because the build dirs that already picked up glog's ON have to converge too.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "link dependencies into libmediapipe_tasks_jni.so" FORCE)

# The dependency layer, all with upstream CMakeLists. This is why ~1600 of the 2378
# objects in Bazel's link line need no generating: abseil, protobuf, XNNPACK, ruy,
# flatbuffers, cpuinfo, pthreadpool, fft2d, farmhash and litert all come from LiteRT.
# LiteRT's CMakeLists declares TFLITE_HOST_TOOLS_DIR and TENSORFLOW_SOURCE_DIR itself
# with `set(... CACHE PATH)`, which drops any same-named normal variable, so these have
# to go into the cache.
set(TFLITE_HOST_TOOLS_DIR "${MP_HOST_TOOLS_DIR}" CACHE PATH "host flatc directory" FORCE)
add_subdirectory("${MP_ROOT}/LiteRT/src/main/cpp" litert)

# XNNPACK's src/log.c calls __android_log_vprint, but its CMakeLists never links liblog:
# under Bazel that comes from the Android crosstool's default linkopts. libXNNPACK.so is
# linked by LiteRT's own rules, so the dependency has to be declared on the object library
# XNNPACK links it through.
target_link_libraries(xnnpack-logging PUBLIC log)

# LiteRT lists only the absl targets it needs for a static tensorflow-lite, where its
# CHECK/LOG references stay unresolved until the final link. Here it is a shared library
# built with -Wl,--no-undefined, so the absl logging targets have to be named.
target_link_libraries(tensorflow-lite PUBLIC absl::log absl::check)

add_subdirectory("${MP_ROOT}/glog/src/main/cpp" glog)
add_subdirectory("${MP_ROOT}/zlib/src/main/cpp" zlib)

# The captured Bazel flags place glog's headers in its source tree, which is where Bazel's
# expand_template writes them. glog 0.6's CMake generates logging.h, raw_logging.h,
# stl_logging.h and vlog_is_on.h into its binary dir, so the object libraries -- which link
# only their flavor target, not glog::glog -- need that directory on the include path.
include_directories("${CMAKE_CURRENT_BINARY_DIR}/glog/glog")

# OpenCV is the one dependency Bazel links rather than compiles. We link the libopencv_java4.so
# and config headers the :opencv module builds and exports to a fixed dir (its own configure),
# not the SDK prebuilt -- the two disagree on HAVE_IPP/HAVE_TBB, so mixing them was an ABI
# hazard. Module headers still come from the source checkout at that same tag, merged into the
# flat layout Bazel's single -I expects.
include("${MP_ROOT}/cmake/opencv_include_tree.cmake")
mp_opencv_include_tree("${MP_ROOT}/opencv/src/main/cpp/opencv"
                       "${MP_ROOT}/opencv/src/main/cpp/export/include/opencv2"
                       "${MP_GEN}/opencv")

add_library(opencv_java4 SHARED IMPORTED)
set_target_properties(opencv_java4 PROPERTIES
  IMPORTED_LOCATION "${MP_ROOT}/opencv/src/main/cpp/export/lib/${ANDROID_ABI}/libopencv_java4.so")

# Consumed by generated/90_link.cmake.
set(MP_DEP_TARGETS
  tensorflow-lite
  protobuf::libprotobuf   # the .pb.cc objects from generated/20_protos.cmake need it
  absl::statusor          # not reachable through tensorflow-lite's absl deps
  absl::status_builder    # same; mediapipe's own StatusBuilder wraps absl's
  glog::glog
  zlibstatic
  opencv_java4)

include(generated/10_common.cmake)       # per-target compile flag flavors
include(generated/20_protos.cmake)       # protoc
include(generated/30_flatbuffers.cmake)  # flatc
include(generated/40_configure.cmake)    # template expansion, descriptor sets
include(generated/45_codegen.cmake)      # barrier every object library waits on
include(generated/50_mediapipe.cmake)    # //mediapipe/... object libraries
include(generated/60_external.cmake)     # icu, re2, sentencepiece, ... object libraries
include(generated/90_link.cmake)         # the shared library itself
