#include <jni.h>
#include <string>
#include "Eigen/Core"

using namespace Eigen;

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_mediapipexes_MainActivity_stringFromJNI(
        JNIEnv* env,
        jobject /* this */) {
    std::string hello = "Hello from C++";
    Eigen::MatrixXd m = Eigen::MatrixXd::Random(3,3);
    return env->NewStringUTF(hello.c_str());
}