# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

# Sets the minimum version of CMake required to build the native library.

cmake_minimum_required(VERSION 3.18.1)

# Declares and names the project.

project("mediapipexes")

#https://gitlab.com/libeigen/eigen
#git checkout -b id_b0f877f8e01e90a5b0f3a79d46ea234899f8b499 b0f877f8e01e90a5b0f3a79d46ea234899f8b499
#tensorflow/src/main/cpp/tensorflow/third_party/eigen3/workspace.bzl
include_directories(eigen)
add_library( # Sets the name of the library.
        eigen

        # Sets the library as a shared library.
        SHARED

        # Provides a relative path to your source file(s).
        native-lib.cpp
        )

# Searches for a specified prebuilt library and stores the path as a
# variable. Because CMake includes system libraries in the search path by
# default, you only need to specify the name of the public NDK library
# you want to add. CMake verifies that the library exists before
# completing its build.

find_library( # Sets the name of the path variable.
        log-lib

        # Specifies the name of the NDK library that
        # you want CMake to locate.
        log)

# Specifies libraries CMake should link to your target library. You
# can link multiple libraries, such as libraries you define in this
# build script, prebuilt third-party libraries, or system libraries.

target_link_libraries( # Specifies the target library.
        eigen
        android
        # Links the target library to the log library
        # included in the NDK.
        ${log-lib})