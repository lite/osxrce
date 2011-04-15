#import <UIKit/UIKit.h>
#import "SampleApp.h"

int main(int argc, char **argv)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    int retVal = UIApplicationMain(argc, argv, nil, [SampleApp class]);
    [pool release];
    return retVal;
}

