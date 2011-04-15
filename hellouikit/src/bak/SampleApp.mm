#import "SampleApp.h"

@implementation SampleApp

- (void) applicationDidFinishLaunching: (id) unused
{
    UIWindow *window;
    // struct CGRect rect = [UIHardware fullScreenApplicationContentRect];
    CGRect rect =CGRectMake(0,0,320,480);
    rect.origin.x = rect.origin.y = 0.0f;

    window = [[UIWindow alloc] initWithContentRect: rect];
    mainView = [[UIView alloc] initWithFrame: rect];
    textView = [[UITextView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, 320.0f, 480.0f)];
    [textView setEditable:YES];
    [textView setTextSize:14];

    [window orderFront: self];
    [window makeKey: self];
    [window _setHidden: NO];
    [window setContentView: mainView];
    [mainView addSubview:textView];

    [textView setText:@"Hello World"];
}

@end

