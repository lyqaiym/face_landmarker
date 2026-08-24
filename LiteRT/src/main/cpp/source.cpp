#include "farmhash.h"
extern "C" {
#include "alloc.h"
}

int test(){
    util::Hash("a",1);
    alloc_1d_int(1);
    return 0;
}