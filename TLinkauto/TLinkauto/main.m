//
//  main.m
//  TLinkauto
//
//  Created by Jason on 2020/12/10.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#include <stdio.h>

static void TLinkautoMainLog(const char *message) {
    FILE *tmp = fopen("/tmp/TLinkauto-main.log", "a");
    if (tmp) {
        fprintf(tmp, "%s\n", message);
        fclose(tmp);
    }

    FILE *library = fopen("/var/mobile/Library/TLinkauto/main.log", "a");
    if (library) {
        fprintf(library, "%s\n", message);
        fclose(library);
    }
}

int main(int argc, char * argv[]) {
    TLinkautoMainLog("main entered before autoreleasepool");
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
        TLinkautoMainLog("main resolved AppDelegate class");
    }
    TLinkautoMainLog("main calling UIApplicationMain");
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
