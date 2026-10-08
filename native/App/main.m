#import <AppKit/AppKit.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        __attribute__((objc_precise_lifetime)) AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
        // objc_precise_lifetime keeps NSApplication's weak delegate alive.
    }
    return 0;
}
