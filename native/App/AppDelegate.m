#import "AppDelegate.h"
#import "OITRequest.h"
#import "TerminalLauncher.h"
#import <FinderSync/FinderSync.h>

@interface AppDelegate ()
@property (nonatomic, strong) NSWindow *setupWindow;
@property (nonatomic, strong) NSTextField *extensionStatus;
@property (nonatomic, strong) TerminalLauncher *launcher;
@property (nonatomic, strong) NSMutableArray<NSURL *> *pendingURLs;
@property (nonatomic) BOOL processingRequest;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _launcher = [[TerminalLauncher alloc] init];
        _pendingURLs = [NSMutableArray array];
    }
    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [self installMainMenu];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
    // AppKit requests an untitled window for an ordinary app launch. URL-driven
    // launches go to openURLs instead, so there is no timed setup-window flash.
    [self showSetup:nil];
    return YES;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showSetup:nil];
    return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self updateExtensionStatus];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    NSAssert([NSThread isMainThread], @"Incoming URLs must be handled on the main thread.");
    [self.pendingURLs addObjectsFromArray:urls];
    [self processNextRequest];
}

- (void)processNextRequest {
    if (self.processingRequest || self.pendingURLs.count == 0) return;
    self.processingRequest = YES;
    NSURL *url = self.pendingURLs.firstObject;
    [self.pendingURLs removeObjectAtIndex:0];

    NSError *validationError = nil;
    OITRequest *request = [OITRequest requestFromURL:url error:&validationError];
    if (request == nil) {
        [self finishRequestWithError:validationError ?: [NSError errorWithDomain:OITTerminalLauncherErrorDomain
            code:5 userInfo:@{NSLocalizedDescriptionKey: @"The folder request could not be read."}]];
        return;
    }
    [self.launcher openRequest:request completion:^(NSError *error) {
        [self finishRequestWithError:error];
    }];
}

- (void)finishRequestWithError:(NSError *)error {
    if (error != nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = error.localizedDescription;
        alert.informativeText = error.localizedRecoverySuggestion ?: @"Make sure the folders are still available, then try again.";
        [alert addButtonWithTitle:@"OK"];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    }
    self.processingRequest = NO;
    // Schedule instead of recursing: requests received during a modal dialog
    // stay serialized, and large batches do not grow the call stack.
    dispatch_async(dispatch_get_main_queue(), ^{ [self processNextRequest]; });
}

- (void)installMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"Open in Terminal" action:NULL keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"Open in Terminal"];

    NSMenuItem *setupItem = [[NSMenuItem alloc] initWithTitle:@"Open in Terminal Setup…" action:@selector(showSetup:) keyEquivalent:@","];
    setupItem.target = self;
    [applicationMenu addItem:setupItem];
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    [applicationMenu addItemWithTitle:@"Hide Open in Terminal" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [applicationMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [applicationMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    [applicationMenu addItemWithTitle:@"Quit Open in Terminal" action:@selector(terminate:) keyEquivalent:@"q"];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:NULL keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight secondary:(BOOL)secondary {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = secondary ? [NSColor secondaryLabelColor] : [NSColor labelColor];
    label.selectable = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

- (NSView *)previewRowWithTitle:(NSString *)title imageName:(NSString *)imageName {
    NSURL *imageURL = [[NSBundle mainBundle] URLForResource:imageName withExtension:@"pdf"];
    NSImage *image = imageURL == nil ? nil : [[NSImage alloc] initWithContentsOfURL:imageURL];
    image.template = YES;
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    imageView.image = image;
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:20],
        [imageView.heightAnchor constraintEqualToConstant:20]
    ]];
    NSTextField *titleLabel = [self label:title size:13 weight:NSFontWeightMedium secondary:NO];
    NSStackView *row = [NSStackView stackViewWithViews:@[imageView, titleLabel]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    return row;
}

- (void)createSetupWindow {
    self.setupWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 490, 410)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.setupWindow.title = @"Open in Terminal";
    self.setupWindow.releasedWhenClosed = NO;
    self.setupWindow.restorable = NO;
    self.setupWindow.delegate = self;

    NSTextField *heading = [self label:@"Open Terminal from Finder" size:22 weight:NSFontWeightSemibold secondary:NO];
    NSTextField *intro = [self label:@"Two actions for folders, directly in the right-click menu." size:13 weight:NSFontWeightRegular secondary:YES];
    NSView *normalRow = [self previewRowWithTitle:@"Open in Terminal" imageName:@"apple.terminal"];
    NSView *windowRow = [self previewRowWithTitle:@"Open in New Terminal Window" imageName:@"apple.terminal.on.rectangle"];
    NSTextField *instructions = [self label:@"Enable Open in Terminal in Finder Extensions, then right-click a folder." size:13 weight:NSFontWeightRegular secondary:NO];
    self.extensionStatus = [self label:@"" size:12 weight:NSFontWeightMedium secondary:YES];
    NSButton *enableButton = [NSButton buttonWithTitle:@"Enable Finder Extension…" target:self action:@selector(openExtensionSettings:)];
    enableButton.bezelStyle = NSBezelStyleRounded;
    enableButton.keyEquivalent = @"\r";
    NSTextField *note = [self label:@"Works with folders on local and mounted volumes. Finder controls the menu position; some search results and virtual locations may not show the actions." size:11 weight:NSFontWeightRegular secondary:YES];

    NSStackView *content = [NSStackView stackViewWithViews:@[heading, intro, normalRow, windowRow, instructions, self.extensionStatus, enableButton, note]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 12;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [content setCustomSpacing:4 afterView:heading];
    [content setCustomSpacing:20 afterView:intro];
    [content setCustomSpacing:20 afterView:windowRow];
    [content setCustomSpacing:6 afterView:instructions];
    [content setCustomSpacing:20 afterView:enableButton];
    [self.setupWindow.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:self.setupWindow.contentView.leadingAnchor constant:28],
        [content.trailingAnchor constraintEqualToAnchor:self.setupWindow.contentView.trailingAnchor constant:-28],
        [content.topAnchor constraintEqualToAnchor:self.setupWindow.contentView.topAnchor constant:28],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:self.setupWindow.contentView.bottomAnchor constant:-24],
        [heading.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [intro.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [instructions.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [note.widthAnchor constraintEqualToAnchor:content.widthAnchor]
    ]];
    [self.setupWindow center];
}

- (void)showSetup:(id)sender {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if (self.setupWindow == nil) [self createSetupWindow];
    [self updateExtensionStatus];
    [self.setupWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)updateExtensionStatus {
    if (self.extensionStatus == nil) return;
    if (@available(macOS 10.14, *)) {
        self.extensionStatus.stringValue = [FIFinderSyncController isExtensionEnabled]
            ? @"Finder extension is enabled."
            : @"Finder extension is not enabled yet.";
    } else {
        self.extensionStatus.stringValue = @"Check Extensions > Finder in System Preferences.";
    }
}

- (void)openExtensionSettings:(id)sender {
    if (@available(macOS 10.14, *)) {
        [FIFinderSyncController showExtensionManagementInterface];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preferences.extensions"]];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == self.setupWindow) {
        // The URL handler stays ready without keeping an otherwise empty Dock app.
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
}

@end
