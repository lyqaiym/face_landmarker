//#include "gflags/gflags.h"
#include "glog/logging.h"
#include "glog/stl_logging.h"
#include <jni.h>

int init = 0;

int main(int argc, char *argv[]) {
    // Initialize Google's logging library.
    google::InitGoogleLogging(argv[0]);
    init = 1;
    // Optional: parse command line flags
//    gflags::ParseCommandLineFlags(&argc, &argv, true);

    LOG(INFO) << "Hello, world!";

    // glog/stl_logging.h allows logging STL containers.
    std::vector<int> x;
    x.push_back(1);
    x.push_back(2);
    x.push_back(3);
    LOG(INFO) << "ABC, it's easy as " << x;

    return 0;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_glog_GlogTest_test(JNIEnv *env, jobject thiz, jstring tag) {
    jboolean isCopy;
    const char *c_tag = env->GetStringUTFChars(tag, &isCopy);
    if (init == 0) {
        init = 1;
        google::InitGoogleLogging(c_tag);
    }
    LOG(INFO) << "Hello, world!INFO";
    LOG(ERROR) << "Hello, world!ERROR";
    LOG(WARNING) << "Hello, world!WARNING";
}