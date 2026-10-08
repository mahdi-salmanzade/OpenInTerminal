#import "FinderSync.h"
#import "OITRequest.h"

#import <AppKit/AppKit.h>

@interface OITFinderSync ()
@property (nonatomic, strong) NSImage *terminalImage;
@property (nonatomic, strong) NSImage *windowMenuImage;
@end

@implementation OITFinderSync

- (instancetype)init {
    self = [super init];
    if (self) {
        _terminalImage = [self menuImageNamed:@"apple.terminal"];
        _windowMenuImage = [self menuImageNamed:@"apple.terminal.on.rectangle"];
        [self updateMonitoredDirectories];

        NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
        for (NSNotificationName name in @[NSWorkspaceDidMountNotification,
                                           NSWorkspaceDidUnmountNotification,
                                           NSWorkspaceDidRenameVolumeNotification]) {
            [center addObserver:self selector:@selector(volumesDidChange:)
                           name:name object:nil];
        }
    }
    return self;
}

- (void)dealloc {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (NSImage *)menuImageNamed:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleForClass:OITFinderSync.class];
    NSURL *URL = [bundle URLForResource:name withExtension:@"pdf"];
    NSImage *source = URL ? [[NSImage alloc] initWithContentsOfURL:URL] : nil;
    if (source.size.width <= 0 || source.size.height <= 0) {
        return nil;
    }

    // Finder serializes menu images into a square slot. Center the original
    // artwork on a square 18-point canvas so it cannot stretch a wide PDF.
    // A concrete 2x bitmap representation also survives that serialization.
    const CGFloat canvasPoints = 18.0;
    const NSInteger canvasPixels = 36;
    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
        pixelsWide:canvasPixels pixelsHigh:canvasPixels
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:representation];
    if (!context) {
        return nil;
    }
    CGFloat scale = MIN(canvasPixels / source.size.width, canvasPixels / source.size.height);
    NSSize artworkSize = NSMakeSize(source.size.width * scale, source.size.height * scale);
    NSRect artworkRect = NSMakeRect((canvasPixels - artworkSize.width) / 2.0,
                                   (canvasPixels - artworkSize.height) / 2.0,
                                   artworkSize.width, artworkSize.height);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    context.imageInterpolation = NSImageInterpolationHigh;
    NSRectFillUsingOperation(NSMakeRect(0, 0, canvasPixels, canvasPixels), NSCompositingOperationClear);
    [source drawInRect:artworkRect fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver fraction:1.0
       respectFlipped:NO hints:nil];
    [NSGraphicsContext restoreGraphicsState];

    representation.size = NSMakeSize(canvasPoints, canvasPoints);
    NSImage *image = [[NSImage alloc] initWithSize:representation.size];
    [image addRepresentation:representation];
    image.template = YES;
    return image;
}

- (void)updateMonitoredDirectories {
    // Finder supplies menu callbacks for these roots and their descendants.
    // This registers scope only: the extension never scans or watches files.
    NSString *home = NSHomeDirectoryForUser(NSUserName()) ?: NSHomeDirectory();
    NSMutableSet<NSURL *> *roots = [NSMutableSet setWithArray:@[
        [NSURL fileURLWithPath:@"/" isDirectory:YES],
        [NSURL fileURLWithPath:home isDirectory:YES],
        [NSURL fileURLWithPath:@"/Volumes" isDirectory:YES]
    ]];
    NSArray<NSURL *> *volumes = [NSFileManager.defaultManager
        mountedVolumeURLsIncludingResourceValuesForKeys:nil options:0];
    if (volumes) {
        [roots addObjectsFromArray:volumes];
    }
    FIFinderSyncController.defaultController.directoryURLs = roots;
}

- (void)volumesDidChange:(NSNotification *)notification {
    if (NSThread.isMainThread) {
        [self updateMonitoredDirectories];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateMonitoredDirectories];
        });
    }
}

- (NSArray<NSURL *> *)folderURLsForMenuKind:(FIMenuKind)kind {
    FIFinderSyncController *controller = FIFinderSyncController.defaultController;
    NSArray<NSURL *> *URLs = nil;

    switch (kind) {
        case FIMenuKindContextualMenuForItems:
            URLs = controller.selectedItemURLs;
            if (URLs.count == 0 && controller.targetedURL) {
                URLs = @[controller.targetedURL];
            }
            break;
        case FIMenuKindContextualMenuForContainer:
        case FIMenuKindContextualMenuForSidebar:
            // A background/sidebar click must not reuse another pane's selection.
            if (controller.targetedURL) {
                URLs = @[controller.targetedURL];
            }
            break;
        case FIMenuKindToolbarItemMenu:
        default:
            return nil;
    }

    if (URLs.count == 0) {
        return nil;
    }
    for (NSURL *URL in URLs) {
        NSNumber *isDirectory = nil;
        if (!URL.isFileURL ||
            ![URL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL] ||
            !isDirectory.boolValue) {
            // Do not offer folder actions for files or mixed selections.
            return nil;
        }
    }
    return [URLs copy];
}

- (NSMenu *)menuForMenuKind:(FIMenuKind)kind {
    NSArray<NSURL *> *folders = [self folderURLsForMenuKind:kind];
    if (folders.count == 0) {
        return nil;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.autoenablesItems = NO;
    [menu addItem:[self menuItemWithTitle:@"Open in Terminal"
                                    mode:OITOpenModeDefault
                                   image:self.terminalImage
                                 folders:folders]];
    [menu addItem:[self menuItemWithTitle:@"Open in New Terminal Window"
                                    mode:OITOpenModeNewWindow
                                   image:self.windowMenuImage
                                 folders:folders]];
    return menu;
}

- (NSMenuItem *)menuItemWithTitle:(NSString *)title
                            mode:(OITOpenMode)mode
                           image:(NSImage *)image
                         folders:(NSArray<NSURL *> *)folders {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                               action:@selector(openFolders:)
                                        keyEquivalent:@""];
    item.target = self;
    item.tag = mode;
    item.image = image;
    // Freeze this menu's selection before Finder's focus can change.
    item.representedObject = [folders copy];
    item.enabled = YES;
    return item;
}

- (void)openFolders:(NSMenuItem *)sender {
    NSError *error = nil;
    NSArray<NSURL *> *folders = [sender.representedObject isKindOfClass:NSArray.class]
        ? sender.representedObject : @[];
    OITRequest *request = [OITRequest requestWithMode:(OITOpenMode)sender.tag
                                         folderURLs:folders
                                              error:&error];
    if (!request) {
        [self showError:error fallback:@"The selected folders are no longer available. Select the folders again and retry."];
        return;
    }

    // Address the app that owns this exact extension, even if another copy or
    // another application has registered the same URL scheme.
    NSURL *applicationURL = [NSBundle bundleForClass:OITFinderSync.class].bundleURL;
    for (NSUInteger index = 0; index < 3; index++) {
        applicationURL = applicationURL.URLByDeletingLastPathComponent;
    }
    NSNumber *isDirectory = nil;
    if (![applicationURL.pathExtension.lowercaseString isEqualToString:@"app"] ||
        ![applicationURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error] ||
        !isDirectory.boolValue) {
        [self showError:error fallback:@"Open in Terminal could not find its containing application. Reinstall the app in Applications and enable its Finder extension again."];
        return;
    }

    // This API supports macOS 10.13. Launch arguments are intentionally unused:
    // macOS ignores them for sandboxed callers, so the request travels as a URL.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSRunningApplication *application = [NSWorkspace.sharedWorkspace
        openURLs:@[request.URL]
        withApplicationAtURL:applicationURL
        options:NSWorkspaceLaunchWithoutActivation
        configuration:@{}
        error:&error];
#pragma clang diagnostic pop
    if (!application) {
        [self showError:error fallback:@"macOS could not launch Open in Terminal. Try opening the app from Applications, then retry this menu action."];
    }
}

- (void)showError:(NSError *)error fallback:(NSString *)fallback {
    dispatch_block_t show = ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"Couldn’t Open Terminal";
        alert.informativeText = error.localizedDescription.length > 0
            ? [NSString stringWithFormat:@"%@\n\n%@", fallback, error.localizedDescription]
            : fallback;
        [alert addButtonWithTitle:@"OK"];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    };
    if (NSThread.isMainThread) {
        show();
    } else {
        dispatch_async(dispatch_get_main_queue(), show);
    }
}

@end
