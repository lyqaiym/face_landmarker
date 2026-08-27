# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

An Android app (Kotlin) based on Google's MediaPipe Face Landmarker demo, with one crucial difference: instead of depending on the prebuilt `com.google.mediapipe:tasks-vision` Maven artifact, it builds the entire MediaPipe Tasks C++ stack (`libmediapipe_tasks_jni.so`), LiteRT (formerly TFLite, `libtensorflow-lite`), and OpenCV (`libopencv_java4.so`) from vendored source via CMake and AGP's `externalNativeBuild`.

The demo UI (`:app`) is the upstream Google Face Landmarker sample; the real work of this repo is the native build pipeline.

## Build

Gradle 8.7, AGP 8.5.1, Kotlin 1.9.24. Toolchain versions live in the `ext` block of the root `build.gradle` (`minSdk 24`, `compileSdk/targetSdk 34`, `ndkVersion 28.2.13676358`, `cmakeVersion`). Only `arm64-v8a` is actually built for the native modules.

- Build the app: `./gradlew :app:assembleDebug`
- Unit test (skeleton only): `./gradlew :app:testDebugUnitTest`
- Build just the native .so: `./gradlew :mediapipe_tasks:externalNativeBuildDebug` (or `:LiteRT:externalNativeBuildDebug` / `:opencv:externalNativeBuildDebug`)

Prerequisites:
- `local.properties` must set `sdk.dir` (gitignored, machine-specific). The root `build.gradle` reads it and exposes `ext.ANDROID_SDK`, which is passed to CMake as `-DANDROID_SDK=...`. It falls back to `ANDROID_HOME` then `ANDROID_SDK_ROOT`.
- NDK `28.2.13676358` must be installed (AGP auto-installs it via `ndkVersion`).
- The `face_landmarker.task` model is auto-downloaded by `app/download_tasks.gradle` on `preBuild` from Google storage into `app/src/main/assets/`.

## Module architecture

The native stack is a three-stage dependency chain, each module building its own `.so` and the next linking it:

1. `:opencv` — builds `libopencv_java4.so` (CMake target `opencv_export`) and exports the `.so` + config headers to `opencv/src/main/cpp/export/` for the next stage to consume.
2. `:LiteRT` — builds `libtensorflow-lite` (CMake target `tensorflow-lite`). All its third-party deps (abseil-cpp, XNNPACK, ruy, eigen, flatbuffers, protobuf, cpuinfo, pthreadpool, gemmlowp, farmhash, etc.) are vendored as git checkouts under `LiteRT/src/main/cpp/<dep>/`.
3. `:mediapipe_tasks` — builds `libmediapipe_tasks_jni.so` (CMake target `mediapipe_tasks_jni`), the JNI layer the app actually loads.

`:app` depends on `:LiteRT`, `:mediapipe_tasks`, and `:opencv` (and guava). Several modules (`:abseil-cpp`, `:eigen`, `:sentencepiece`, `:mediapipelib`) are commented out in `settings.gradle` and no longer part of the build.

## `:mediapipe_tasks` and the Bazel → CMake codegen

`mediapipe_tasks/src/main/cpp/CMakeLists.txt` is deliberately thin — it only declares the dependency layer (`add_subdirectory` on LiteRT/glog/zlib, the imported `opencv_java4` shared lib, and the `MP_DEP_TARGETS` list). The actual object libraries and link line live in `mediapipe_tasks/src/main/cpp/generated/*.cmake`, which are **generated and must not be hand-edited**.

Those files are produced by `tools/bazel2cmake/` from `bazel aquery` dumps of the `//mediapipe/tasks/java/com/google/mediapipe/tasks/core:libmediapipe_tasks_jni.so` target in the `mediapipesource/` Bazel workspace (a google-ai-edge/mediapipe checkout). Regenerate only when `mediapipesource/` BUILD files change:

```
tools/bazel2cmake/regen.sh
```

Day-to-day Android Studio builds consume the committed `.cmake` files and need neither Bazel nor Python.

## Vendoring third-party source

`flatbuffers.sh` is an idempotent, one-shot script that reproduces the entire vendored dependency tree: it clones every third-party repo at a pinned commit/tag (pinned in the `MODULES` / `LITERT_DEPS` variables), applies the patches under `tools/patches/`, and builds the host `flatc` into `build/host-flatc` (referenced by `:LiteRT` via `TFLITE_HOST_TOOLS_DIR`). Run it once on a fresh checkout; it skips anything already present.

Patches in `tools/patches/` fix CMake-only compilation issues (audio_tools C++ fixes, icu udata, sentencepiece, stb_image impls, and `litert_custom_ops.diff` which adds the MediaPipe GPU custom operators that LiteRT v2.1.6 does not ship). Bazel's own BUILD/`.bzl` patches are intentionally not applied here because CMake compiles the `.cc/.h` sources directly.

## Conventions and gotchas

- **C++ standard is `c++20`** for `:mediapipe_tasks` and `:LiteRT` (`:opencv` uses `c++17`). This is required to keep `absl::SourceLocation`/`absl::Status` types consistent with Bazel's compile, otherwise out-of-line `MakeErrorImpl` instantiations fail to link.
- **`targets` in each module's `externalNativeBuild.cmake` config is load-bearing**: AGP otherwise builds every discovered shared-library target (and ignores CMake's `EXCLUDE_FROM_ALL`), pulling in ~1600 unwanted targets and failing on things like missing `Python.h`.
- **`BUILD_SHARED_LIBS OFF`** is forced (with `CACHE ... FORCE`) in `mediapipe_tasks` CMakeLists so every dependency links statically into the single `.so`; glog's `option(BUILD_SHARED_LIBS ... ON)` would otherwise poison cached build dirs on reconfigure.
- **CameraX is pinned to `1.4.2`** in `:app`: `1.3.4`'s `libimage_processing_util_jni.so` is 4KB-aligned and fails to load on 16KB-page devices.
- OpenCV's `.so` and config headers are built from the vendored `4.12.0` source, not the SDK prebuilt — the two disagree on `HAVE_IPP`/`HAVE_TBB`, and mixing them is an ABI hazard (see `cmake/opencv_include_tree.cmake`).
- The generated CMake + vendored-source directories (`*/src/main/cpp/<dep>`, `mediapipesource/`, `build/`) are untracked by git; only the scripts and committed `.cmake` files are source-controlled.
