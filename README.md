mediapipelib
https://github.com/google-ai-edge/mediapipe
export ANDROID_HOME=~/android/sdk
export ANDROID_NDK_HOME=~/android/sdk/ndk/23.2.8568313
按 setup_android_sdk_and_ndk.sh 最后几行在 WORKSPACE 加入下面几句
android_sdk_repository(name = "androidsdk")
android_ndk_repository(name = "androidndk", api_level=26)
bind(name = "android/crosstool", actual = "@androidndk//:toolchain")
register_toolchains("@androidsdk//:all", "@androidndk//:all")

bazel build -c opt --config=android_arm64 //mediapipe/tasks/java/com/google/mediapipe/tasks/core:libmediapipe_tasks_jni.so
编译出
libmediapipe_tasks_jni.so
放入 mediapipelib/libs/arm64-v8a 下面