# LiteRT (tflite) 交叉编译说明

## FlatBuffers：用的是 google/flatbuffers，不是 flatcc

`LiteRT/tflite` 依赖的是 **google/flatbuffers（C++ 实现）**：`tflite` 下有 100+ 个文件 include
`flatbuffers/flatbuffers.h`，`tflite/tools/cmake/modules/flatbuffers.cmake` 也是从
`https://github.com/google/flatbuffers` 拉源码。宿主工具叫 **`flatc`**。

`LiteRT/src/main/cpp/flatcc`（dvidelabs/flatcc）是另一套**纯 C** 实现，工具叫 `flatcc`，两者不兼容。
它在 LiteRT 里只被 2 个文件用到：`tflite/core/acceleration/configuration/c/xnnpack_plugin_c_test_lib.c`
及其 `BUILD`，属于 XNNPack delegate C-API 的**测试辅助代码**，不是主库依赖。所以
`TFLITE_HOST_TOOLS_DIR` 必须放 google/flatbuffers 的 `flatc`，flatcc 顶替不了。

实际参与编译的 flatbuffers 源码是 **`LiteRT/src/main/cpp/flatbuffers`**（当前 25.12.19，由顶层
`CMakeLists.txt` 直接 `add_subdirectory` 引入）。根目录那份 `flatbuffers/`（23.1.21）是给别的模块用的，
**不要拿它编 flatc**。

## 问题 1：缺少宿主机 flatc

```
CMake Error at LiteRT/tflite/CMakeLists.txt:110 (message):
  When cross-compiling, some tools need to be available to run on the host
  (current required tools: flatc).  Please specify where those binaries can
  be found by using -DTFLITE_HOST_TOOLS_DIR=<flatc_dir_path>.
```

原因：tflite 构建过程中要用 `flatc` 生成 FlatBuffers 头文件。交叉编译到 Android 时编出来的 `flatc`
是 arm64 Android 可执行文件，宿主机（macOS）跑不了，所以必须额外提供一个宿主机版 `flatc`。

### 解决：编译宿主机版 flatc

在项目根目录执行（源码用 LiteRT 自己那份，保证版本一致）：

```bash
cmake -S LiteRT/src/main/cpp/flatbuffers -B build/host-flatc \
  -DCMAKE_BUILD_TYPE=Release \
  -DFLATBUFFERS_BUILD_TESTS=OFF \
  -DFLATBUFFERS_INSTALL=OFF \
  -DFLATBUFFERS_BUILD_FLATLIB=OFF \
  -DFLATBUFFERS_BUILD_FLATHASH=OFF
cmake --build build/host-flatc --target flatc -j8
```

产物 `build/host-flatc/flatc`，验证版本：

```bash
./build/host-flatc/flatc --version   # flatc version 25.12.19
```

**版本必须和 `LiteRT/src/main/cpp/flatbuffers/include/flatbuffers/base.h` 里的
`FLATBUFFERS_VERSION_*` 完全一致**。flatc 生成的头文件带 `static_assert` 版本校验，版本不一致会在
编译期报 `Non-compatible flatbuffers version included`。别用 `brew install flatbuffers` 的系统版本。

### 传给 CMake

`LiteRT/build.gradle` 已配好，Gradle 构建自动带上：

```groovy
externalNativeBuild {
    cmake {
        arguments "-DTFLITE_HOST_TOOLS_DIR=" + new File(rootProject.projectDir, "build/host-flatc").absolutePath
        arguments "-DFLATBUFFERS_BUILD_FLATC=OFF"   // 不为 Android 编 flatc，用宿主机那份
        ...
    }
}
```

配置成功日志：

```
-- Pre-built 'flatc' compiler for cross-compilation purposes found: .../build/host-flatc/flatc
```

## 问题 2：flatbuffers::flatbuffers target 不存在

```
CMake Error at LiteRT/tflite/examples/label_image/CMakeLists.txt:70 (add_executable):
  Target "label_image" links to target "flatbuffers::flatbuffers" but the
  target was not found.
```

原因链：

1. 顶层 `CMakeLists.txt` 直接 `add_subdirectory(flatbuffers)`，target `flatbuffers` 提前存在。
2. tflite 的 `find_package(FlatBuffers)`（`tflite/CMakeLists.txt:195`）→ `FindFlatBuffers.cmake`
   → `include(flatbuffers)`，而 `flatbuffers.cmake:16` 的
   `if(TARGET flatbuffers OR flatbuffers_POPULATED) return()` 直接短路返回。
3. 创建 alias 的那行 `add_library(flatbuffers::flatbuffers ALIAS flatbuffers)` 被
   `if(flatbuffers_POPULATED)` 包着，于是从没执行。
4. 本地 flatbuffers 25.12.19 自己只定义 `flatbuffers`（`CMakeLists.txt:441`）和
   `FlatBuffers::FlatBuffers`（`:729`），没有小写的 `flatbuffers::flatbuffers`。
5. `tensorflow-lite` 是 PUBLIC 链接 `flatbuffers::flatbuffers`（`tflite/CMakeLists.txt:781`），
   所以所有下游 target 都炸。`label_image` 即使被 `EXCLUDE_FROM_ALL`，`add_executable` 仍会执行，
   生成阶段照样报错。

### 解决：自己补上 alias

顶层 `LiteRT/src/main/cpp/CMakeLists.txt`：

```cmake
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/flatbuffers)
if(NOT TARGET flatbuffers::flatbuffers)
  add_library(flatbuffers::flatbuffers ALIAS flatbuffers)
endif()
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/LiteRT/tflite)
```

（另一条路是删掉顶层的 `add_subdirectory(flatbuffers)`，改成传
`-DFETCHCONTENT_SOURCE_DIR_FLATBUFFERS=<本地路径>`，让 tflite 走它自己的 FetchContent 流程，
alias 就会正常创建。当前采用的是上面补 alias 的方案。）

## 问题 3：Could NOT find Python（ml_dtypes）

```
CMake Error at .../Modules/FindPackageHandleStandardArgs.cmake:165 (message):
  Could NOT find Python (missing: Python_EXECUTABLE Python_INCLUDE_DIRS ...)
```

原因：顶层直接 `add_subdirectory(ml_dtypes)` 引入的是**上游 ml_dtypes 的 CMakeLists**，它第 4 行就
`find_package(Python REQUIRED COMPONENTS Interpreter Development.Module)`，然后用 `Python_add_library`
编 Python 扩展模块 `_ml_dtypes_ext`（还要 numpy 头文件），并且内部会 `add_subdirectory(third_party/eigen)`
跟本地 eigen 撞 target。这套东西交叉编译到 Android 完全用不上。

注意报错的是 `Python`（不是 `Python3`），所以设 `Python3_EXECUTABLE` 没用；而且它要的是 Python
头文件，NDK 工具链的 `CMAKE_FIND_ROOT_PATH` 限制下本来也找不到宿主机的。

### 解决：改用 tflite 自带的 header-only 包装层

tflite 只需要一个 INTERFACE target，它自己带了包装层
`LiteRT/tflite/tools/cmake/modules/ml_dtypes/CMakeLists.txt`（只做 `add_library(ml_dtypes INTERFACE)`
+ include 目录，不碰 Python）。顶层 `CMakeLists.txt` 改成：

```cmake
set(ML_DTYPES_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ml_dtypes" CACHE PATH "" FORCE)
add_subdirectory(
  ${CMAKE_CURRENT_SOURCE_DIR}/LiteRT/tflite/tools/cmake/modules/ml_dtypes
  ${CMAKE_BINARY_DIR}/ml_dtypes-build
)
set(ml_dtypes_FOUND TRUE)
```

最后一行是让 `Findml_dtypes.cmake` 走进 `if(ml_dtypes_FOUND OR ml_dtypes_POPULATED)` 分支，由它自己
创建 `ml_dtypes::ml_dtypes` alias —— 所以这里不用像 flatbuffers 那样手写 alias。

include 路径能对上：tflite 里写的是 `#include "ml_dtypes/include/float8.h"`
（`tflite/kernels/internal/float8.h:18`），包装层给的正是 ml_dtypes 根目录。

配置成功时日志里会出现 `TARGET ml_dtypes1` —— 那是 `ml_dtypes.cmake` 检测到 target 已存在提前
return 的调试输出，说明成功绕开了 FetchContent。

## 通用套路：本地依赖 vs tflite 的 FetchContent

问题 2 和问题 3 是同一个模式。tflite 的每个第三方依赖都有一对
`tools/cmake/modules/Find<Pkg>.cmake` + `<pkg>.cmake`，结构都是：

```cmake
# <pkg>.cmake
if(TARGET <pkg> OR <pkg>_POPULATED)
  return()                      # ← 本地已 add_subdirectory 时从这里短路
endif()
... FetchContent 下载 ...

# Find<Pkg>.cmake
include(<pkg>)
if(<pkg>_POPULATED)             # ← 短路后这里是 false
  add_library(<pkg>::<pkg> ALIAS <pkg>)   # ← alias 不会被创建
endif()
```

所以只要在顶层 `add_subdirectory` 了某个依赖来避免联网，就要自己补上 `<pkg>::<pkg>` alias
（或者设 `<pkg>_FOUND TRUE` 让 Find 模块自己补）。下游报
`links to target "xxx::xxx" but the target was not found` 基本都是这个原因。

另一条路是保留 tflite 的流程，用 `-DFETCHCONTENT_SOURCE_DIR_<UPPERCASE_NAME>=<本地路径>`
指向本地源码，这样 `_POPULATED` 会被正常设置，alias 也会自动创建。

## 命令行单独验证配置（不走 Gradle）

```bash
cmake -S LiteRT/src/main/cpp -B temp/cfg-check \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_SDK/ndk/28.2.13676358/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
  -DTFLITE_HOST_TOOLS_DIR=$PWD/build/host-flatc \
  -DGOOGLETEST_PATH=$PWD/googletest/src/main/cpp/googletest \
  -DFLATBUFFERS_BUILD_FLATC=OFF \
  -DCMAKE_BUILD_TYPE=Debug
```

## 注意

`build/host-flatc` 在根目录 `build/` 下，`gradle clean` 或手动清理 `build/` 会把 `flatc` 删掉，
之后配置又会报问题 1 —— 重新执行上面的编译命令即可。

`LiteRT/tflite/tools/cmake/modules/ml_dtypes.cmake` 里目前有两行排查用的调试语句
（`message(WARNING "TARGET ml_dtypes1")` 和 `message(FATAL_ERROR "TARGET ml_dtypes2")`）。
现在因为提前 return 走不到那个 `FATAL_ERROR`，但一旦哪天 target 不存在了就会直接炸，属于地雷，
排查完建议删掉。
