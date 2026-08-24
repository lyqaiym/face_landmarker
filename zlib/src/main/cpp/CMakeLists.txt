cmake_minimum_required(VERSION 3.10)

project(zlibso)

include_directories(~/AndroidStudioProjects/mediapipegesture/zlib/.cxx/Debug/6of2k3uu/arm64-v8a/zlib)
include_directories(./zlib)
#add_definitions(-DSTDC)
add_subdirectory(./zlib)

add_library(zlibso SHARED source.cpp)

target_link_libraries(zlibso)