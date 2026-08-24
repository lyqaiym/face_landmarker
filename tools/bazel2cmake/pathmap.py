"""Bazel path -> CMake path expression mapping.

The one hand-maintained table in the generator. Anything not covered is reported as
unmapped and fails the run, so a missing dependency can never pass silently.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass, field

# Variables the emitted CMake defines.
ROOT = "${MP_ROOT}"      # repo root
SRC = "${MP_SRC}"        # <root>/mediapipesource, i.e. the Bazel workspace root
GEN = "${MP_GEN}"        # output of our own codegen rules

LITERT = f"{ROOT}/LiteRT/src/main/cpp"
TF = f"{ROOT}/tensorflow/src/main/cpp/tensorflow"
NDK = "${MP_NDK}"        # stand-in for @androidndk's repo root; see the CMakeLists

# Deps that already have an upstream CMakeLists under LiteRT/src/main/cpp and are built
# by that module's add_subdirectory calls. Mapped for include paths only; their compile
# targets are never regenerated.
LITERT_REPOS = {
    "abseil-cpp~": "abseil-cpp",
    "protobuf~": "protobuf",
    "litert": "LiteRT",
    "XNNPACK": "XNNPACK",
    "cpuinfo": "cpuinfo",
    "pthreadpool": "pthreadpool",
    "FXdiv": "FXdiv",
    "FP16": "FP16",
    "flatbuffers": "flatbuffers",
    "ruy": "ruy",
    "gemmlowp": "gemmlowp",
    "eigen": "eigen",
    "eigen_archive": "eigen",
    "farmhash_archive": "farmhash",
    "fft2d": "OouraFFT-1.0",
    "ml_dtypes": "ml_dtypes",
}

# Packages inside a LiteRT repo whose generated files emit.py reproduces -- see its
# GEN_LABELS. Those belong in the codegen output tree; writing them back into a git
# checkout that only ships some of them would be both dirty and version-dependent.
LITERT_GEN_PACKAGES = {
    "litert": ("tflite/delegates/gpu/",),
}

# The LiteRT checkout is newer than the aquery capture, and upstream's GPU flatbuffer
# schemas name their sibling .fbs files by the pre-split `tensorflow/lite/...` prefix even
# though the files themselves sit under `tflite/`. The single -I Bazel recorded -- the litert
# repo root -- therefore cannot resolve those includes; the aquery capture predates the
# regression, so its own copies still say `tflite/`.
#
# Those same schemas exist at exactly the included path in the tensorflow checkout, so flatc
# gets that root as a second -I and reads the siblings from there. The alternative is a
# one-line patch per .fbs in the LiteRT checkout, which works but leaves the tree dirty.
# Safe because the two prefixes cannot shadow each other: nothing resolves under both roots.
LITERT_ROOT = f"{LITERT}/{LITERT_REPOS['litert']}"
FBS_INCLUDE_ROOT = TF  # the root `tensorflow/lite/...` resolves against


def fbs_sibling_in_tf(path: str) -> str | None:
    """A litert schema's path in the tensorflow checkout, i.e. the copy flatc will open.

    Only the dependency edges need this; flatc finds the file from FBS_INCLUDE_ROOT. Returns
    None for a schema that is not under the litert checkout.
    """
    prefix = f"{LITERT_ROOT}/tflite/"
    if not path.startswith(prefix):
        return None
    return f"{TF}/tensorflow/lite/{path[len(prefix):]}"


# Deps with their own checkout in this repo, most of them a Gradle module. Mapped to the
# checkout root; unlike LITERT_REPOS these have no CMakeLists we use, so their compile
# lines are regenerated from the Bazel graph like mediapipe's own.
MODULE_REPOS = {
    # @@zlib//:zlib and @@zlib~//:z are two Bazel repos over the same upstream zlib;
    # both link into the .so. emit.py collapses them into one CMake target.
    "zlib": f"{ROOT}/zlib/src/main/cpp/zlib",
    "zlib~": f"{ROOT}/zlib/src/main/cpp/zlib",
    "com_github_glog_glog": f"{ROOT}/glog/src/main/cpp/glog",
    "com_github_glog_glog_no_gflags": f"{ROOT}/glog/src/main/cpp/glog",
    "com_github_gflags_gflags": f"{ROOT}/glog/src/main/cpp/gflags",
    "org_tensorflow": TF,
    # Cloned at commit dcd5bede6859d26833cd85f0d6bbcee7382dc9b3, the commit TF's
    # WORKSPACE pins via tf_http_archive. Header-only.
    "opencl_headers": f"{ROOT}/mediapipe_tasks/src/main/cpp/third_party/OpenCL-Headers",
    # Cloned at tag 2025-11-05, the version MODULE.bazel.lock resolves re2 to.
    "re2~": f"{ROOT}/re2/src/main/cpp/re2",
    # Cloned at the commit WORKSPACE pins, with third_party/com_google_audio_tools_fixes.diff
    # applied -- Bazel patches the archive, so an unpatched checkout would not compile.
    "com_google_audio_tools": f"{ROOT}/audio_tools/src/main/cpp/audio_tools",
    # Cloned at 7c3b5a7dc510, the revision WORKSPACE's bitbucket archive URL names.
    "pffft": f"{ROOT}/pffft/src/main/cpp/pffft",
    # Not declared in WORKSPACE -- icu comes in through @org_tensorflow//third_party/icu,
    # which pins tag release-69-1 and applies udata.patch. Cloned at that tag with the patch
    # applied; the icu4j/ jars stay LFS pointers since only icu4c/ reaches the compile lines.
    "icu": f"{ROOT}/icu/src/main/cpp/icu",
    # Cloned at tag v0.1.96 with third_party/com_google_sentencepiece.diff applied. WORKSPACE's
    # add_prefix="sentencepiece" wraps the archive, so the Bazel repo root (and every emitted
    # path) carries a sentencepiece/ prefix; the clone therefore sits one level deeper than
    # the other checkouts, at sentencepiece/src/main/cpp/sentencepiece/sentencepiece.
    "com_google_sentencepiece": f"{ROOT}/sentencepiece/src/main/cpp/sentencepiece",
    # Cloned at tag v2.20.0 with tensorflow_text_remove_tf_deps.diff and
    # tensorflow_text_stub_pywrap.diff applied -- Bazel patches the archive, so an
    # unpatched checkout would not match what the aquery dumps were captured against.
    "org_tensorflow_text": f"{ROOT}/tensorflow_text/src/main/cpp/tensorflow_text",
    # Cloned at commit b42009b3b9d4ca35bc703f5310eedc74f584be58 with
    # third_party/stb_image_impl.diff applied -- the patch adds the stb_image.c /
    # stb_image_write.c impl files, so an unpatched checkout has no .c to compile.
    "stblib": f"{ROOT}/stblib/src/main/cpp/stblib",
    # Cloned at commit 87b71afd6cf784953e3c08f24c64203397f3b724. Header-only: only
    # include/darts.h reaches the compile lines (as a bare -iquote root), no .cc.
    "darts_clone": f"{ROOT}/darts_clone/src/main/cpp/darts_clone",
    # Cloned at commit 32c07c0c5334aea069e518206d75e002ccd85389. Header-only. Bazel's
    # link_files injects tensorflow/vulkan_hpp_dispatch_loader_dynamic.cc from org_tensorflow,
    # but that .cc does not reach the compile lines, so the plain checkout is sufficient.
    "vulkan_headers": f"{ROOT}/vulkan_headers/src/main/cpp/vulkan_headers",
}

# MODULE repos whose generated files (protoc/genrule outputs) emit.py actually reproduces,
# so those outputs go to MP_GEN instead of the checkout. sentencepiece is the only one: its
# .pb.cc/.pb.h and config.h are Bazel-generated and absent from the upstream clone. Other
# MODULE repos (icu, re2, ...) ship their generated headers in the checkout already.
MODULE_CODEGEN_REPOS = {"com_google_sentencepiece"}

# Bazel-only plumbing, or owned by the CMake toolchain.
DROP_REPOS = {
    "androidsdk",
    "bazel_tools",
    "apple_support~",
    "rules_cc~",
    "rules_python",
    "build_bazel_rules_android",
    "coral_crosstool",
    # Reachable only from litert's own translation units: Bazel's .d files show no
    # mediapipe source ever opens an xla/ or tsl/ header.
    "xla",
    "tsl",
}

# OpenCV is the one dependency Bazel does not compile: it links the prebuilt
# libopencv_java4.so from the Android SDK release, contributing none of the 2378 objects.
# Bazel's compile lines carry a single -I into that SDK's flat install include dir. The source
# checkout under opencv/ splits the same headers across modules/<mod>/include, so
# cmake/opencv_include_tree.cmake merges them back into the install layout under MP_GEN and
# that one directory is what the emitted flag targets point at. Only cvconfig.h and
# opencv_modules.hpp still come from the SDK -- they describe the prebuilt's configuration,
# so no checkout can produce them; vendor.sh copies just those two.
OPENCV_INCLUDES = [f"{GEN}/opencv/include"]

# Bazel synthesizes a `_virtual_includes/<x>` symlink forest for every cc_library that
# re-roots its headers via strip_include_prefix/include_prefix. Those dirs exist only
# under bazel-out; in a plain checkout the same headers sit under one real include root
# per repo, so every virtual dir collapses to it.
VIRTUAL_INCLUDE_ROOTS = {
    "protobuf~": f"{LITERT}/protobuf/src",
    "flatbuffers": f"{LITERT}/flatbuffers/include",
    "FP16": f"{LITERT}/FP16/include",
    "FXdiv": f"{LITERT}/FXdiv/include",
    "cpuinfo": f"{LITERT}/cpuinfo/include",
    "pthreadpool": f"{LITERT}/pthreadpool/include",
    # glog 0.8.0's checkout ships real headers; the few generated ones (export.h,
    # config.h) come in as usage requirements of the glog::glog target we link.
    "com_github_glog_glog": f"{ROOT}/glog/src/main/cpp/glog/src",
    "com_github_glog_glog_no_gflags": f"{ROOT}/glog/src/main/cpp/glog/src",
}

_BAZEL_OUT = re.compile(r"^bazel-out/(?P<cfg>[^/]+)/(?P<kind>[^/]+)(?:/(?P<rest>.*))?$")
_EXTERNAL = re.compile(r"^external/(?P<repo>[^/]+)(?:/(?P<rest>.*))?$")
# Bazel's per-target object output dirs; CMake owns object placement.
_OBJS = re.compile(r"(^|/)_objs/")
# `_virtual_imports/<x>` are protoc -I dirs holding copies of the well-known .proto
# files, which live in the protobuf checkout proper.
_VIRTUAL_IMPORTS = re.compile(r"/_virtual_imports/[^/]+$")
_VIRTUAL_INCLUDES = re.compile(r"(^|/)_virtual_includes/")
_OPENCV_INCLUDE = "android_opencv/sdk/native/jni/include"


@dataclass
class Mapped:
    """`paths` empty means intentionally dropped."""

    paths: list[str]
    generated: bool = False
    host: bool = False


DROPPED = Mapped(paths=[])


def _is_host_config(cfg: str) -> bool:
    return "-exec-" in cfg or cfg.startswith(("darwin", "k8", "host"))


@dataclass
class PathMapper:
    unmapped: Counter[str] = field(default_factory=Counter)

    def map(self, path: str) -> Mapped:
        path = path.rstrip("/")
        if not path or path == ".":
            return Mapped(paths=[SRC])

        m = _BAZEL_OUT.match(path)
        if m:
            if m["kind"] != "bin":
                return DROPPED  # _middlemen, _solib_*, internal bookkeeping
            if _is_host_config(m["cfg"]):
                return Mapped(paths=[], host=True)
            rest = m["rest"] or ""
            if not rest:
                return Mapped(paths=[GEN], generated=True)
            return self._map_workspace_relative(rest, generated=True)

        return self._map_workspace_relative(path, generated=False)

    def _map_workspace_relative(self, path: str, generated: bool) -> Mapped:
        if _OBJS.search(path) or path.endswith((".o", ".d", ".a", ".so")):
            return DROPPED

        m = _EXTERNAL.match(path)
        if not m:
            if path.startswith("mediapipe/") or path == "mediapipe":
                base = GEN if generated else SRC
                return Mapped(paths=[f"{base}/{path}"], generated=generated)
            self.unmapped[path] += 1
            return DROPPED

        repo, rest = m["repo"], m["rest"] or ""

        if repo in DROP_REPOS:
            return DROPPED

        if repo == "androidndk":
            # The toolchain owns everything the NDK provides except cpufeatures, which
            # mediapipe/util/cpu_util.cc reaches as "ndk/sources/android/cpufeatures/...".
            # @androidndk exposes that tree both with and without the `ndk/` prefix and
            # Bazel compiles cpu-features.c once per form; they are the same file, so
            # normalize onto the prefixed one and let emit.py dedupe.
            tail = rest[4:] if rest.startswith("ndk/") else rest
            if not rest:
                return Mapped(paths=[NDK])
            if tail.startswith("sources/android/cpufeatures"):
                return Mapped(paths=[f"{NDK}/ndk/{tail}"])
            return DROPPED

        if _VIRTUAL_INCLUDES.search(rest):
            root = VIRTUAL_INCLUDE_ROOTS.get(repo)
            if root is None:
                self.unmapped[f"external/{repo}/_virtual_includes/..."] += 1
                return DROPPED
            return Mapped(paths=[root])

        if repo == "android_opencv":
            # Bazel passes the repo root as an -I alongside the real include dir; only the
            # latter resolves `opencv2/...`, so the root is redundant here.
            if not rest:
                return DROPPED
            if f"{repo}/{rest}" == _OPENCV_INCLUDE or rest == "sdk/native/jni/include":
                return Mapped(paths=list(OPENCV_INCLUDES))
            return self._opencv_header(rest)

        if repo in LITERT_REPOS:
            if _VIRTUAL_IMPORTS.search(rest):
                return Mapped(paths=[f"{LITERT}/protobuf/src"])
            checkout = self._join(f"{LITERT}/{LITERT_REPOS[repo]}", rest)
            prefixes = LITERT_GEN_PACKAGES.get(repo)
            if generated and prefixes:
                if not rest:
                    # Bazel's -I for the repo's generated root. Only the packages above are
                    # regenerated, so the checkout has to stay on the search path too.
                    return Mapped(paths=[f"{GEN}/external/{repo}", checkout], generated=True)
                if rest.startswith(prefixes):
                    return Mapped(paths=[f"{GEN}/external/{repo}/{rest}"], generated=True)
            # zlib~'s public headers are staged by a genrule into bazel-out; the real
            # ones sit in the checkout, so generated and source forms coincide.
            return Mapped(paths=[checkout])

        if repo in MODULE_REPOS:
            # Most MODULE checkouts already ship their generated files (icu's headers), so
            # those resolve from the checkout. A repo whose protoc/genrule outputs emit.py
            # reproduces is the exception: those outputs belong in MP_GEN rather than
            # dirtying the clone.
            if generated and repo in MODULE_CODEGEN_REPOS:
                return Mapped(
                    paths=[f"{GEN}/external/{repo}/{rest}".rstrip("/")], generated=True
                )
            return Mapped(paths=[self._join(MODULE_REPOS[repo], rest)])

        if generated:
            return Mapped(paths=[f"{GEN}/external/{repo}/{rest}".rstrip("/")], generated=True)

        self.unmapped[f"external/{repo}/{rest}"] += 1
        return DROPPED

    def _opencv_header(self, rest: str) -> Mapped:
        """Rebase `sdk/native/jni/include/opencv2/<x>` onto the vendored SDK include dir."""
        marker = "sdk/native/jni/include/"
        if marker not in rest:
            self.unmapped[f"external/android_opencv/{rest}"] += 1
            return DROPPED
        tail = rest.split(marker, 1)[1]
        return Mapped(paths=[f"{inc}/{tail}" for inc in OPENCV_INCLUDES])

    @staticmethod
    def _join(prefix: str, rest: str) -> str:
        return f"{prefix}/{rest}" if rest else prefix

    def report(self) -> str:
        lines = [f"{count:6d}  {path}" for path, count in self.unmapped.most_common()]
        return "\n".join(lines) + ("\n" if lines else "")
