//
//  Hello_WorldAppDelegate.h
//  Hello World
//
//  Created by ktundwal on 3/7/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MyView;

@interface Hello_WorldAppDelegate : NSObject {
    UIWindow *window;
    MyView *contentView;
}

@property (nonatomic, retain) UIWindow *window;
@property (nonatomic, retain) MyView *contentView;

@end
