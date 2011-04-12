#import <UIKit/UIKit.h>
#import <UIKit/UIApplication.h>
#include <dlfcn.h>
#include <stdio.h>

// Framework Paths
#define SBSERVPATH "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"
#define UIKITPATH "/System/Library/Framework/UIKit.framework/UIKit"

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    //
    // For testing try issuing the following: 
    // ap y; sleep 5; ./ap n
    //

    if (argc < 2)
    {
        printf("Usage: %s (y | n)\n", argv[0]);
        exit(-1);
    }

    // Fetch the SpringBoard server port
    mach_port_t *p;
    void *uikit = dlopen(UIKITPATH, RTLD_LAZY);
    int (*SBSSpringBoardServerPort)() = 
    dlsym(uikit, "SBSSpringBoardServerPort");
    p = SBSSpringBoardServerPort(); 
    dlclose(uikit);

    // Link to SBSetAirplaneModeEnabled
    void *sbserv = dlopen(SBSERVPATH, RTLD_LAZY);
    // int (*setAPMode)(mach_port_t* port, BOOL yorn) = dlsym(sbserv, "SBSetAirplaneModeEnabled");
    // // Argument used to switch airplane mode off or on
    // BOOL yorn = [[[NSString stringWithCString:argv[1]] uppercaseString] hasPrefix:@"Y"];
    // setAPMode(p, yorn);
    int (*dataReset)(mach_port_t* port) = dlsym(sbserv, "SBDataReset");
    dataReset(p);
    dlclose(sbserv);

    [pool release];
}