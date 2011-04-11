//
// Simple bundle driver
//
#include <stdio.h>
#include <stdlib.h>
#include <err.h>
#include <dlfcn.h>

int main(int argc, char* argv[])
{
    void* dl_handle;

    if (argc < 2) {
        fprintf(stderr, "usage: %s <path to bundle>\n", argv[0]);
        exit(EXIT_FAILURE);
    }
  
    dl_handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (dl_handle) {
        int (*run)(int);
        run = dlsym(dl_handle, "run");
        if (run != NULL) {
            return run(0);
        }
    }
    else {
        errx(EXIT_FAILURE, "dlopen: %s", dlerror());
    }

    return 0;
}
