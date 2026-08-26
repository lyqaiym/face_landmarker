#!/bin/bash
# 一次性搭建 libmediapipe_tasks_jni.so 的全部第三方源码,并编出宿主 flatc。
#
# 这个脚本复现当前(已编译通过)的依赖树。每一个依赖都是 git 仓库,钉到"现在
# checkout 里恰好是哪个 commit / tag",不是 HEAD。
#
# 与 Bazel 的关系:路径布局以 tools/bazel2cmake/pathmap.py 为准(见 MODULE_REPOS /
# LITERT_REPOS)。OouraFFT 的 tag v1.0 和 Bazel 的 WORKSPACE 钉的
# OouraFFT-1.0 归档对应同一份源码。
#
# 补丁只打影响 CMake 编译的:audio_tools 的 C++ 源码修复、icu 的 udata 修复、
# sentencepiece 的源码修复、stblib 补上 stb_image.c/stb_image_write.c 实现文件、
# LiteRT 补上 mediapipe GPU 自定义算子(v2.1.6 原生一个都没有,全靠 litert_custom_ops.diff)。
# tensorflow/abseil/tensorflow_text 在 Bazel 里的那些 patch 只改 BUILD/.bzl,
# CMake 编的是 .cc/.h,所以不打。LiteRT 的 rules_python/fbs_fix 同理(生成器已处理)。
#
# 幂等:每个目录已存在就跳过,所以中断后重跑只会补上缺的部分。换个干净目录从头跑
# 一遍得到的是同一棵树。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES="$ROOT/tools/patches"

# 依赖版本钉死在这里,而不是散落在几十条 clone 命令里。
# 模块依赖:目标目录是 <dep>/src/main/cpp/<dep>(pathmap 的 MODULE_REPOS)。
MODULES="
  audio_tools/src/main/cpp/audio_tools|git@github.com:google/multichannel-audio-tools.git|bbf15de4b7cd825d650296d21917afc07e8fe18b
  re2/src/main/cpp/re2|git@github.com:google/re2.git|927f5d53caf8111721e734cf24724686bb745f55
  zlib/src/main/cpp/zlib|https://github.com/madler/zlib.git|e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca
  glog/src/main/cpp/glog|https://github.com/google/glog.git|b33e3bad4c46c8a6345525fd822af355e5ef9446
  glog/src/main/cpp/gflags|https://github.com/gflags/gflags.git|03a4842c9c6aaef438d7bf0c84e8a62c8064992b
  icu/src/main/cpp/icu|git@github.com:unicode-org/icu.git|release-69-1
  opencv/src/main/cpp/opencv|https://github.com/opencv/opencv.git|4.12.0
  pffft/src/main/cpp/pffft|https://bitbucket.org/jpommier/pffft.git|7c3b5a7dc510a0f513b9c5b6dc5b56f7aeeda422
  sentencepiece/src/main/cpp/sentencepiece/sentencepiece|git@github.com:google/sentencepiece.git|v0.1.96
  stblib/src/main/cpp/stblib|https://github.com/nothings/stb.git|b42009b3b9d4ca35bc703f5310eedc74f584be58
  darts_clone/src/main/cpp/darts_clone|git@github.com:s-yata/darts-clone.git|87b71afd6cf784953e3c08f24c64203397f3b724
  vulkan_headers/src/main/cpp/vulkan_headers|git@github.com:KhronosGroup/Vulkan-Headers.git|32c07c0c5334aea069e518206d75e002ccd85389
  tensorflow/src/main/cpp/tensorflow|https://github.com/tensorflow/tensorflow.git|a481b10260dfdf833a1b16007eead49c1d7febf3
  tensorflow_text/src/main/cpp/tensorflow_text|git@github.com:tensorflow/text.git|v2.20.0
  mediapipe_tasks/src/main/cpp/third_party|git@github.com:KhronosGroup/OpenCL-Headers.git
"

# LiteRT 层的依赖,目标目录是 LiteRT/src/main/cpp/<dep>。flatbuffers/protobuf 之外
# 都没有 tag,钉 commit。
LITERT_DEPS="
  LiteRT|git@github.com:google-ai-edge/LiteRT.git|v2.1.6
  abseil-cpp|https://github.com/abseil/abseil-cpp.git|20260526.0
  benchmark|git@github.com:google/benchmark.git|3a0d9e02550058aa6c578e9fe20a311e641ba31f
  cpuinfo|https://github.com/pytorch/cpuinfo|66ee79c038d70dad9f08705b2c9b3e58f6d8f512
  eigen|https://gitlab.com/libeigen/eigen.git|59208527c57d9e2a0d4a15466df868b6147e3f77
  farmhash|https://github.com/google/farmhash|0d859a811870d10f53a594927d0d0b97573ad06d
  flatbuffers|git@github.com:google/flatbuffers.git|v25.9.23
  FP16|https://github.com/Maratyszcza/FP16.git|782eea126dc5c755827be751a099eb01826175cf
  FXdiv|https://github.com/Maratyszcza/FXdiv.git|63058eff77e11aa15bf531df5dd34395ec3017c8
  gemmlowp|https://github.com/google/gemmlowp|16e8662c34917be0065110bfcd9cc27d30f52fdf
  googletest|git@github.com:google/googletest.git|a2118f6587e09ac822798394a5f9736eba002555
  kleidiai|https://gitlab.arm.com/kleidi/kleidiai.git|6787251d9cc2f38a3a6024b11fd7ace10cde4cd9
  ml_dtypes|https://github.com/jax-ml/ml_dtypes|d09882f7cfed1158c76dd95cb95aa1643f2af61b
  protobuf|https://github.com/protocolbuffers/protobuf.git|74211c0dfc2777318ab53c2cd2c317a2ef9012de
  pthreadpool|https://github.com/google/pthreadpool.git|02460584c6092e527c8b89f7df4de143d70e801f
  ruy|https://github.com/google/ruy|2264753777198e4393fb83c44c693462d57a2be1
  XNNPACK|https://github.com/google/XNNPACK.git|8388bd78690515166d59f1b28e593a455a41d580
  OouraFFT-1.0|git@github.com:petewarden/OouraFFT.git|v1.0
"

# 全部依赖都是 git 仓库,统一按 commit / tag clone,不再有归档下载。
command -v git >/dev/null || { echo "git 未安装" >&2; exit 1; }

# 幂等 clone。已经存在的目录直接跳过;ref 形如 tag/branch 用 --depth 1 快照,纯 commit
# 只能完整 clone 再 checkout(服务端默认不允许按 SHA 浅取)。
clone() { # <dest-relative-path> <url> <ref>
  local dest="$ROOT/$1" url="$2" ref="$3"
  if [ -d "$dest" ]; then
    echo "skip   $1 (已存在)"
    return 0
  fi
  echo "clone  $1 @ $ref"
  mkdir -p "$(dirname "$dest")"
  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    git clone "$url" "$dest"
    git -C "$dest" checkout --quiet "$ref"
  else
    git clone --depth 1 --branch "$ref" "$url" "$dest"
  fi
}

for m in $MODULES; do
  IFS='|' read -r dest url ref <<< "$m"
  clone "$dest" "$url" "$ref"
done
for m in $LITERT_DEPS; do
  IFS='|' read -r name url ref <<< "$m"
  clone "LiteRT/src/main/cpp/$name" "$url" "$ref"
done

# 打补丁。git 格式和 diff -ru 格式都能被 patch -p1 接受;全部在仓库根目录里打。
# 幂等:先 --reverse --dry-run 判断是否已经打过(打过就跳过),否则 --forward 应用。
# 不能只依赖 .flatbuffers_patched 标记 —— 盘上已有的 checkout 可能早就是打过补丁的树,
# 但没有这个标记,而 patch --forward 在 hunk 已应用时退出码是 1。
apply() { # <dest-relative-path> <patch-file...>
  local dest="$ROOT/$1"; shift
  local p
  for p in "$@"; do
    if ( cd "$dest" && patch -p1 --reverse --dry-run < "$PATCHES/$p" >/dev/null 2>&1 ); then
      echo "skip   $1 <- $(basename "$p") (已打过)"
    else
      echo "patch  $1 <- $(basename "$p")"
      ( cd "$dest" && patch -p1 --forward < "$PATCHES/$p" )
    fi
  done
}

apply "audio_tools/src/main/cpp/audio_tools" audio_tools_fixes.diff
apply "icu/src/main/cpp/icu" icu_udata.patch
apply "sentencepiece/src/main/cpp/sentencepiece" sentencepiece.diff
apply "stblib/src/main/cpp/stblib" stb_image_impl.diff
# LiteRT 的 mediapipe GPU 自定义算子:v2.1.6 原生没有这四个 mediapipe 目录
# (common/tasks/selectors/gl 的 mediapipe),全由 Bazel 的 litert_custom_ops.diff 提供;
# BUILD 修改 CMake 用不到但一并打上,对齐 Bazel 树。rules_python/fbs_fix 不需要(见上)。
apply "LiteRT/src/main/cpp/LiteRT" litert_custom_ops.diff
# tensorflow 的 WORKSPACE patch(org_tensorflow_*.diff)只改 BUILD/.bzl,CMake 编译的是
# .cc/.h,所以这里不打 —— 干净归档即可。abseil、tensorflow_text 同理(见上)。

# 编出宿主 flatc。mediapipe_tasks 走 cmake/host_tools.cmake 自己那份;这份是
# LiteRT/build.gradle:22 里的 TFLITE_HOST_TOOLS_DIR 指向的 build/host-flatc。
echo "build  flatc"
mkdir -p "$ROOT/build"
cmake -S "$ROOT/LiteRT/src/main/cpp/flatbuffers" -B "$ROOT/build/host-flatc" \
  -DCMAKE_BUILD_TYPE=Release \
  -DFLATBUFFERS_BUILD_FLATC=ON \
  -DFLATBUFFERS_BUILD_TESTS=OFF \
  -DFLATBUFFERS_INSTALL=OFF \
  -DFLATBUFFERS_BUILD_FLATLIB=OFF \
  -DFLATBUFFERS_BUILD_FLATHASH=OFF
cmake --build "$ROOT/build/host-flatc" --target flatc -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)"

echo
echo "完成。flatc 在 $ROOT/build/host-flatc/flatc"
