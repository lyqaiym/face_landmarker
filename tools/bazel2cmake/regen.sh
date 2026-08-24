#!/bin/bash
# Re-dump the Bazel build graph and regenerate mediapipe_tasks/src/main/cpp/generated/.
#
# Only needed when the mediapipesource/ BUILD files change. Day-to-day Android Studio
# builds consume the committed .cmake files and need neither bazel nor Python.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/mediapipesource"
TARGET='//mediapipe/tasks/java/com/google/mediapipe/tasks/core:libmediapipe_tasks_jni.so'
CONFIG=(--config=android_arm64 -c opt)

# @androidndk resolves through this; without it analysis of the .so target fails outright.
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"

dump() {
  local out="$1" filter="$2"
  echo ">>> aquery $out"
  # Into a temp file, then move: a shell redirect would truncate the committed dump
  # before bazel runs, and a failed aquery would leave nothing to fall back on.
  (cd "$SRC" && set -x && bazel aquery "${CONFIG[@]}" \
    "mnemonic(\"$filter\", deps($TARGET))" \
    --output=jsonproto --include_artifacts=true) >"$SRC/$out.tmp"
  mv "$SRC/$out.tmp" "$SRC/$out"
}

dump compile_actions.json 'CppCompile'
dump genproto_actions.json 'GenProto'
dump codegen_actions.json 'CppArchive|CppLink|GenProtoDescriptorSet|Genrule|TemplateExpand'

echo ">>> generating cmake"
exec python3 "$ROOT/tools/bazel2cmake/main.py" --dumps "$SRC" \
  --out "$ROOT/mediapipe_tasks/src/main/cpp/generated"
