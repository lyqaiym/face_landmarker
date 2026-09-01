#!/usr/bin/env bash
#
# Regenerate the MediaPipe Tasks Java protobuf classes (*Proto.java) from the
# .proto files in the mediapipesource/ Bazel checkout, into
# mediapipe_tasks/src/main/generated/proto/.
#
# The Java API sources live in mediapipesource/ (srcDirs in mediapipe_tasks/build.gradle)
# and import these generated classes. Keep this list in sync with the protos those
# sources import. Run after mediapipesource/ BUILD/.proto files change:
#
#   tools/gen_java_protos.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="mediapipe_tasks/src/main/generated"

# Host protoc matching the vendored protobuf (31.1) is built as a side effect of the
# :mediapipe_tasks CMake build. Locate it under the .cxx cache.
PROTOC=$(find mediapipe_tasks/.cxx -name 'protoc-31.1.0' -type f 2>/dev/null | head -1)
if [[ -z "$PROTOC" ]]; then
  echo "error: protoc-31.1.0 not found; build the native module once first" >&2
  exit 1
fi

# Well-known types (google/protobuf/*.proto) ship in the vendored protobuf source.
PROTOBUF_SRC="LiteRT/src/main/cpp/protobuf/src"

PROTOS=(
  mediapipe/calculators/core/flow_limiter_calculator.proto
  mediapipe/calculators/tensor/inference_calculator.proto
  mediapipe/framework/calculator.proto
  mediapipe/framework/calculator_options.proto
  mediapipe/framework/calculator_profile.proto
  mediapipe/framework/deps/proto_descriptor.proto
  mediapipe/framework/formats/annotation/rasterization.proto
  mediapipe/framework/formats/classification.proto
  mediapipe/framework/formats/detection.proto
  mediapipe/framework/formats/landmark.proto
  mediapipe/framework/formats/location_data.proto
  mediapipe/framework/formats/matrix_data.proto
  mediapipe/framework/formats/rect.proto
  mediapipe/framework/mediapipe_options.proto
  mediapipe/framework/packet_factory.proto
  mediapipe/framework/packet_generator.proto
  mediapipe/framework/status_handler.proto
  mediapipe/framework/stream_handler.proto
  mediapipe/framework/tool/calculator_graph_template.proto
  mediapipe/gpu/gpu_origin.proto
  mediapipe/util/label_map.proto
  mediapipe/tasks/cc/audio/audio_classifier/proto/audio_classifier_graph_options.proto
  mediapipe/tasks/cc/components/containers/proto/classifications.proto
  mediapipe/tasks/cc/components/containers/proto/embeddings.proto
  mediapipe/tasks/cc/components/processors/proto/classifier_options.proto
  mediapipe/tasks/cc/components/processors/proto/embedder_options.proto
  mediapipe/tasks/cc/core/proto/acceleration.proto
  mediapipe/tasks/cc/core/proto/base_options.proto
  mediapipe/tasks/cc/core/proto/external_file.proto
  mediapipe/tasks/cc/text/text_classifier/proto/text_classifier_graph_options.proto
  mediapipe/tasks/cc/text/text_embedder/proto/text_embedder_graph_options.proto
  mediapipe/tasks/cc/vision/face_detector/proto/face_detector_graph_options.proto
  mediapipe/tasks/cc/vision/face_geometry/calculators/geometry_pipeline_calculator.proto
  mediapipe/tasks/cc/vision/face_geometry/proto/face_geometry.proto
  mediapipe/tasks/cc/vision/face_geometry/proto/face_geometry_graph_options.proto
  mediapipe/tasks/cc/vision/face_geometry/proto/mesh_3d.proto
  mediapipe/tasks/cc/vision/face_landmarker/proto/face_blendshapes_graph_options.proto
  mediapipe/tasks/cc/vision/face_landmarker/proto/face_landmarker_graph_options.proto
  mediapipe/tasks/cc/vision/face_landmarker/proto/face_landmarks_detector_graph_options.proto
  mediapipe/tasks/cc/vision/gesture_recognizer/proto/gesture_classifier_graph_options.proto
  mediapipe/tasks/cc/vision/gesture_recognizer/proto/gesture_embedder_graph_options.proto
  mediapipe/tasks/cc/vision/gesture_recognizer/proto/gesture_recognizer_graph_options.proto
  mediapipe/tasks/cc/vision/gesture_recognizer/proto/hand_gesture_recognizer_graph_options.proto
  mediapipe/tasks/cc/vision/hand_detector/proto/hand_detector_graph_options.proto
  mediapipe/tasks/cc/vision/hand_landmarker/proto/hand_landmarker_graph_options.proto
  mediapipe/tasks/cc/vision/hand_landmarker/proto/hand_landmarks_detector_graph_options.proto
  mediapipe/tasks/cc/vision/hand_landmarker/proto/hand_roi_refinement_graph_options.proto
  mediapipe/tasks/cc/vision/holistic_landmarker/proto/holistic_landmarker_graph_options.proto
  mediapipe/tasks/cc/vision/image_classifier/proto/image_classifier_graph_options.proto
  mediapipe/tasks/cc/vision/image_embedder/proto/image_embedder_graph_options.proto
  mediapipe/tasks/cc/vision/image_generator/diffuser/stable_diffusion_iterate_calculator.proto
  mediapipe/tasks/cc/vision/image_generator/proto/conditioned_image_graph_options.proto
  mediapipe/tasks/cc/vision/image_generator/proto/control_plugin_graph_options.proto
  mediapipe/tasks/cc/vision/image_generator/proto/image_generator_graph_options.proto
  mediapipe/tasks/cc/vision/image_segmenter/calculators/tensors_to_segmentation_calculator.proto
  mediapipe/tasks/cc/vision/image_segmenter/proto/image_segmenter_graph_options.proto
  mediapipe/tasks/cc/vision/image_segmenter/proto/segmenter_options.proto
  mediapipe/tasks/cc/vision/interactive_segmenter/proto/stroke.proto
  mediapipe/tasks/cc/vision/interactive_segmenter_legacy/proto/region_of_interest.proto
  mediapipe/tasks/cc/vision/object_detector/proto/object_detector_options.proto
  mediapipe/tasks/cc/vision/pose_detector/proto/pose_detector_graph_options.proto
  mediapipe/tasks/cc/vision/pose_landmarker/proto/pose_landmarker_graph_options.proto
  mediapipe/tasks/cc/vision/pose_landmarker/proto/pose_landmarks_detector_graph_options.proto
  mediapipe/tasks/java/com/google/mediapipe/tasks/genai/llminference/jni/proto/llm_options.proto
  mediapipe/tasks/java/com/google/mediapipe/tasks/genai/llminference/jni/proto/llm_response_context.proto
)

rm -rf "$OUT"
mkdir -p "$OUT"

"$PROTOC" -I mediapipesource -I "$PROTOBUF_SRC" --java_out=lite:"$OUT" "${PROTOS[@]}"

# TasksStatsLoggerFactory.java is produced by a Bazel genrule in
# mediapipe/tasks/java/com/google/mediapipe/tasks/core/BUILD; reproduce it here.
FACTORY="$OUT/com/google/mediapipe/tasks/core/logging/TasksStatsLoggerFactory.java"
mkdir -p "$(dirname "$FACTORY")"
cat > "$FACTORY" <<'EOF'
package com.google.mediapipe.tasks.core.logging;

import android.content.Context;

public final class TasksStatsLoggerFactory {
  public static TasksStatsLogger create(
      Context context, String taskNameStr, String taskRunningModeStr) {
    return TasksStatsDummyLogger.create(context, taskNameStr, taskRunningModeStr);
  }
}
EOF

echo "generated $(find "$OUT" -name '*.java' | wc -l | tr -d ' ') java files into $OUT"