# Recreate OpenCV's install-time include layout from the source checkout.
#
# Bazel never compiles OpenCV: it compiles against @android_opencv, the prebuilt Android SDK
# release, whose include dir is the flat result of an install -- one opencv2/ with every
# module merged -- and links libopencv_java4.so out of the same zip. The source checkout
# instead keeps each module's headers under modules/<mod>/include/opencv2/, so the single
# -I Bazel recorded cannot resolve them.
#
# Each module owns exactly opencv2/<mod>/ plus the umbrella opencv2/<mod>.hpp and nothing
# else, so merging them is collision-free and one link per entry reproduces the install tree.
# Symlinks rather than copies: the merged tree then cannot hold a stale copy of a header, and
# clang's -MD records the link path while stat() follows it, so ninja still notices edits in
# the checkout.

# The version @android_opencv pins -- see the http_archive in mediapipesource/WORKSPACE:
# opencv-4.12.0-android-sdk.zip. The headers have to come from the same release as the
# prebuilt .so, and a checkout left on another tag fails this in a way git will not show you:
# `git status` stays clean while 300-odd headers differ.
set(MP_OPENCV_VERSION "4.12.0")

# The modules present in that SDK's include dir. Deliberately not a glob over modules/*:
# the checkout also carries ts and world, which the SDK does not ship and nothing includes.
set(MP_OPENCV_MODULES
  calib3d core dnn features2d flann gapi highgui imgcodecs
  imgproc ml objdetect photo stitching video videoio)

function(_mp_opencv_link original linkname)
  message(WARNING "original=${original}")
  message(WARNING "linkname=${linkname}")
  if(NOT EXISTS "${original}")
    message(FATAL_ERROR "opencv include tree: missing ${original}")
  endif()
  file(REMOVE "${linkname}")
  file(CREATE_LINK "${original}" "${linkname}" SYMBOLIC)
endfunction()

# checkout: the OpenCV source tree.  generated: the opencv2/ dir the opencv module's own
# configure produced, holding cvconfig.h and opencv_modules.hpp.  out_dir: gets an
# include/opencv2/ that one -I can resolve.
function(mp_opencv_include_tree checkout generated out_dir)
  set(version_h "${checkout}/modules/core/include/opencv2/core/version.hpp")
  if(NOT EXISTS "${version_h}")
    message(FATAL_ERROR
      "opencv include tree: no OpenCV checkout at ${checkout}\n"
      "  expected ${version_h}")
  endif()
  file(STRINGS "${version_h}" _v REGEX "^#define CV_VERSION_(MAJOR|MINOR|REVISION) ")
  string(REGEX REPLACE "[^0-9;]" "" _v "${_v}")
  string(REPLACE ";" "." _found "${_v}")
  if(NOT _found STREQUAL "${MP_OPENCV_VERSION}")
    message(FATAL_ERROR
      "opencv include tree: ${checkout} is ${_found}, but libopencv_java4.so comes from the "
      "${MP_OPENCV_VERSION} SDK release.\n"
      "  Run: git -C ${checkout} checkout ${MP_OPENCV_VERSION}")
  endif()

  set(opencv2 "${out_dir}/include/opencv2")
  file(MAKE_DIRECTORY "${opencv2}")
  foreach(mod IN LISTS MP_OPENCV_MODULES)
    set(root "${checkout}/modules/${mod}/include/opencv2")
    _mp_opencv_link("${root}/${mod}" "${opencv2}/${mod}")
    _mp_opencv_link("${root}/${mod}.hpp" "${opencv2}/${mod}.hpp")
  endforeach()
  _mp_opencv_link("${checkout}/include/opencv2/opencv.hpp" "${opencv2}/opencv.hpp")

  # cvconfig.h and opencv_modules.hpp describe how the .so was configured (HAVE_IPP, HAVE_TBB,
  # which HAVE_OPENCV_* exist), so they belong to the .so, not to the source tree, and no
  # checkout can supply them. They now come from the opencv module's own configure (exported
  # to a fixed dir), so the macros always match the libopencv_java4.so mediapipe links -- the
  # SDK prebuilt had IPP/TBB on while the module build has them off, and mixing the two was an
  # ODR/ABI hazard. Both are load-bearing: opencv2/core/base.hpp includes opencv_modules.hpp,
  # and mediapipe/framework/port/opencv_core_inc.h includes cvconfig.h.
  foreach(h cvconfig.h opencv_modules.hpp)
    _mp_opencv_link("${generated}/${h}" "${opencv2}/${h}")
  endforeach()
endfunction()
