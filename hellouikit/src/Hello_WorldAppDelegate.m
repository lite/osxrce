//
//  Hello_WorldAppDelegate.m
//  Hello World
//
//  Created by ktundwal on 3/7/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "Hello_WorldAppDelegate.h"
#import "MyView.h"

@implementation Hello_WorldAppDelegate

@synthesize window;
@synthesize contentView;

- (void)applicationDidFinishLaunching:(UIApplication *)application {	
	// Create window
	self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    
    // Set up content view
	self.contentView = [[[MyView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
	[window addSubview:contentView];
	
	UIView      *mainView;
	UITextView  *textView;
	
	mainView = [[UIView alloc] initWithFrame: [[UIScreen mainScreen] bounds]];
    textView = [[UITextView alloc]
				initWithFrame: CGRectMake(10.0f, 10.0f, 320.0f, 480.0f)];
    [textView setEditable:YES];

    //[textView setTextSize:14];
	
    //[window orderFront: self];
    //[window makeKey: self];
    //[window _setHidden: NO];
    [window addSubview: mainView];
    [mainView addSubview:textView];
	
    [textView setText:@"Hello World"];
	
    
	// Show window
	[window makeKeyAndVisible];
}

- (void)dealloc {
	[contentView release];
	[window release];
	[super dealloc];
}

@end
