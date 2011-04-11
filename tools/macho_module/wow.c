#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <err.h>
#include <sys/param.h>
#include <mach-o/dyld.h>

#include "mach_override.h"

/**********************************************************************
 *                               Hooks                                *
 **********************************************************************/
int (*_real_NSCreateObjectFileImageFromMemory)(const void* address, size_t size, NSObjectFileImage* objectFileImage);
int _hook_NSCreateObjectFileImageFromMemory(const void* address, size_t size, NSObjectFileImage* objectFileImage){
	
	// call the original function!
	int res = (*_real_NSCreateObjectFileImageFromMemory)(address, size, objectFileImage);
	
	// save the module to a file :-)
	char name[100];
	snprintf(name, sizeof(name), "/0x%X_0x%X.bin", (unsigned int)address, (unsigned int)size);
	printf("WRITING module to %s\n", name);
	int fd = open(name, O_WRONLY|O_CREAT|O_TRUNC, 0600);
	if (fd > 0) {
		// pretty straightforward, we know the start address of where the module is stored within wow's memory
		//	and we know the size!
		write(fd, address, size);
	}
	close(fd);

	return res;	
}


/**********************************************************************
 *                         Bundle Interface                           *
 **********************************************************************/
static void init(void) __attribute__ ((constructor));
void init(void)
{
    mach_error_t me;

	me = mach_override(	"_NSCreateObjectFileImageFromMemory", NULL,
	 (void*)&_hook_NSCreateObjectFileImageFromMemory,
	 (void**)&_real_NSCreateObjectFileImageFromMemory);

	warnx("Was the hook successful? %x %s", me, mach_error_string(me));
}
