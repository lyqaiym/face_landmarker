cmake_minimum_required(VERSION 3.10)

project(opencv)

add_subdirectory(./opencv)

# 把 OpenCV 自己 configure/build 生成的配置头 + libopencv_java4.so 导出到固定目录
# export/,供 mediapipe_tasks 模块引用。路径里没有 .cxx 的配置哈希,mediapipe_tasks 才能
# 稳定引用;同时保证头文件(cvconfig.h/opencv_modules.hpp 的宏)和 .so 出自同一次
# configure,不再和 SDK 预编译的那份混用。
set(OPENCV_EXPORT "${CMAKE_CURRENT_SOURCE_DIR}/export")

# 配置头在 configure 阶段就位,直接复制。
file(MAKE_DIRECTORY "${OPENCV_EXPORT}/include/opencv2")
file(COPY "${CMAKE_BINARY_DIR}/opencv2/cvconfig.h"
          "${CMAKE_BINARY_DIR}/opencv2/opencv_modules.hpp"
     DESTINATION "${OPENCV_EXPORT}/include/opencv2")

# libopencv_java4.so 在 build 阶段生成。opencv_java 定义在 add_subdirectory(./opencv)
# 的子目录里,这里不能用 add_custom_command(TARGET ...)(要求 target 在当前目录),改用
# custom target 跨目录依赖。
add_custom_target(opencv_export ALL
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${OPENCV_EXPORT}/lib/${ANDROID_ABI}"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
          "$<TARGET_FILE:opencv_java>"
          "${OPENCV_EXPORT}/lib/${ANDROID_ABI}/libopencv_java4.so"
  DEPENDS opencv_java
  VERBATIM)
