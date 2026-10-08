#import "TerminalLauncher.h"
#import "OITRequest.h"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

NSErrorDomain const OITTerminalLauncherErrorDomain = @"io.openinterminal.app.TerminalLauncher";

@implementation TerminalLauncher

- (void)openRequest:(OITRequest *)request completion:(void (^)(NSError * _Nullable))completion {
    NSAssert([NSThread isMainThread], @"Terminal requests must be handled on the main thread.");

    NSURL *terminalURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
    if (terminalURL == nil) {
        completion([NSError errorWithDomain:OITTerminalLauncherErrorDomain code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"Terminal could not be found.",
            NSLocalizedRecoverySuggestionErrorKey: @"Make sure Apple's Terminal app is available in Applications > Utilities."
        }]);
        return;
    }

    if (request.mode == OITOpenModeNewWindow) {
        completion([self openNewWindowsForFolders:request.folderURLs]);
        return;
    }

    NSError *error = nil;
    // This public API supports the 10.13 deployment target and hands directories
    // to Terminal without constructing or executing a shell command.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSRunningApplication *application = [[NSWorkspace sharedWorkspace]
        openURLs:request.folderURLs
        withApplicationAtURL:terminalURL
        options:NSWorkspaceLaunchDefault | NSWorkspaceLaunchWithoutAddingToRecents
        configuration:@{}
        error:&error];
#pragma clang diagnostic pop
    if (application == nil && error == nil) {
        error = [NSError errorWithDomain:OITTerminalLauncherErrorDomain code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"Terminal could not open the selected folders."
        }];
    }
    completion(error);
}

- (nullable NSError *)openNewWindowsForFolders:(NSArray<NSURL *> *)folderURLs {
    NSURL *scriptURL = [[NSBundle mainBundle] URLForResource:@"OpenNewTerminalWindow" withExtension:@"scpt"];
    NSDictionary *loadError = nil;
    NSAppleScript *script = scriptURL == nil ? nil : [[NSAppleScript alloc] initWithContentsOfURL:scriptURL error:&loadError];
    if (script == nil) {
        NSMutableDictionary *details = [@{
            NSLocalizedDescriptionKey: @"The Terminal window helper could not be loaded.",
            NSLocalizedRecoverySuggestionErrorKey: @"Reinstall Open in Terminal and try again."
        } mutableCopy];
        if (loadError[NSAppleScriptErrorMessage] != nil) {
            details[NSLocalizedFailureReasonErrorKey] = loadError[NSAppleScriptErrorMessage];
        }
        return [NSError errorWithDomain:OITTerminalLauncherErrorDomain code:3 userInfo:details];
    }

    NSAppleEventDescriptor *paths = [NSAppleEventDescriptor listDescriptor];
    NSInteger index = 1;
    for (NSURL *folderURL in folderURLs) {
        NSData *pathData = [folderURL.path dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedPath = [pathData base64EncodedStringWithOptions:0];
        [paths insertDescriptor:[NSAppleEventDescriptor descriptorWithString:encodedPath] atIndex:index++];
    }

    // Only printable ASCII base64 reaches Terminal's PTY. Raw path control
    // characters must not be interpreted by terminal line editing or the shell.
    NSAppleEventDescriptor *arguments = [NSAppleEventDescriptor listDescriptor];
    [arguments insertDescriptor:paths atIndex:1];
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor
        appleEventWithEventClass:kASAppleScriptSuite eventID:kASSubroutineEvent
        targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"openfolders"] forKeyword:keyASSubroutineName];
    [event setParamDescriptor:arguments forKeyword:keyDirectObject];
    NSDictionary *scriptError = nil;
    NSAppleEventDescriptor *result = [script executeAppleEvent:event error:&scriptError];
    if (result != nil) return nil;

    NSInteger code = [scriptError[NSAppleScriptErrorNumber] integerValue];
    if (code == 0) code = 4;
    NSString *description = scriptError[NSAppleScriptErrorMessage] ?: @"Terminal could not open a new window.";
    NSMutableDictionary *details = [@{NSLocalizedDescriptionKey: description} mutableCopy];
    if (code == errAEEventNotPermitted) {
        details[NSLocalizedDescriptionKey] = @"Permission to open a new Terminal window was not granted.";
        details[NSLocalizedRecoverySuggestionErrorKey] = @"In System Settings (or System Preferences), open Privacy & Security > Automation and allow Open in Terminal to control Terminal. You can still use the Open in Terminal menu action without this permission.";
    }
    return [NSError errorWithDomain:OITTerminalLauncherErrorDomain code:code userInfo:details];
}

@end
