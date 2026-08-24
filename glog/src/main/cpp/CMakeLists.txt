cmake_minimum_required(VERSION 3.10)

project(glog)

add_definitions(-DGOOGLE_STRIP_LOG=0)
add_definitions(-DGLOG_BAZEL_BUILD=1)
add_definitions(-DHAVE_STRING_H=1)
#add_subdirectory(gflags)
add_subdirectory(glog)

include_directories(glog/src)

add_library(glog_so SHARED source.cpp)

target_link_libraries(glog_so glog::glog)