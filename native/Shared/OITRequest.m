#import "OITRequest.h"

static const NSUInteger OITMaximumFolders = 128;
static const NSUInteger OITMaximumURLLength = 131072;

static void OITSetError(NSError **error, NSString *description) {
    if (error) {
        *error = [NSError errorWithDomain:@"io.openinterminal.request" code:1
                                userInfo:@{NSLocalizedDescriptionKey: description}];
    }
}

@implementation OITRequest

+ (instancetype)requestWithMode:(OITOpenMode)mode folderURLs:(NSArray<NSURL *> *)folderURLs
                         error:(NSError **)error {
    if (mode != OITOpenModeDefault && mode != OITOpenModeNewWindow) {
        OITSetError(error, @"Unknown Terminal action.");
        return nil;
    }
    if (folderURLs.count == 0 || folderURLs.count > OITMaximumFolders) {
        OITSetError(error, @"Select between 1 and 128 folders.");
        return nil;
    }

    NSMutableOrderedSet<NSURL *> *folders = [NSMutableOrderedSet orderedSet];
    for (NSURL *URL in folderURLs) {
        if (![URL isKindOfClass:NSURL.class] || !URL.isFileURL || !URL.path.isAbsolutePath ||
            (URL.host.length && ![URL.host isEqualToString:@"localhost"]) ||
            URL.query || URL.fragment || URL.user || URL.password || URL.port) {
            OITSetError(error, @"Only local folder paths are accepted. Mounted disks use their local paths.");
            return nil;
        }
        NSNumber *isDirectory = nil;
        NSError *resourceError = nil;
        if (![URL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError] ||
            !isDirectory.boolValue) {
            OITSetError(error, [NSString stringWithFormat:@"This folder is unavailable: %@", URL.path]);
            return nil;
        }
        // Preserve the original path: resolving symlinks or '..' changes which folder the user selected.
        [folders addObject:[NSURL fileURLWithPath:URL.path isDirectory:YES]];
    }

    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObjects:
        [NSURLQueryItem queryItemWithName:@"version" value:@"1"],
        [NSURLQueryItem queryItemWithName:@"mode"
                                  value:mode == OITOpenModeNewWindow ? @"new-window" : @"default"], nil];
    for (NSURL *folder in folders) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"folder" value:folder.absoluteString]];
    }
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"openinterminal-app";
    components.host = @"open";
    components.queryItems = items;
    NSURL *requestURL = components.URL;
    if (!requestURL || requestURL.absoluteString.length > OITMaximumURLLength) {
        OITSetError(error, @"The selected folder paths are too long. Try fewer folders at once.");
        return nil;
    }
    OITRequest *request = [[self alloc] init];
    request->_mode = mode;
    request->_folderURLs = folders.array.copy;
    request->_URL = requestURL;
    return request;
}

+ (instancetype)requestFromURL:(NSURL *)URL error:(NSError **)error {
    if (URL.absoluteString.length > OITMaximumURLLength) {
        OITSetError(error, @"The Terminal request is too long.");
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    if (![components.scheme isEqualToString:@"openinterminal-app"] ||
        ![components.host isEqualToString:@"open"] || components.path.length ||
        components.user || components.password || components.port || components.fragment) {
        OITSetError(error, @"This is not a valid Open in Terminal request.");
        return nil;
    }
    NSString *version = nil;
    NSString *mode = nil;
    NSMutableArray<NSURL *> *folders = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"version"] && !version && item.value) {
            version = item.value;
        } else if ([item.name isEqualToString:@"mode"] && !mode && item.value) {
            mode = item.value;
        } else if ([item.name isEqualToString:@"folder"] && item.value.length) {
            NSURL *folder = [NSURL URLWithString:item.value];
            if (!folder) {
                OITSetError(error, @"A folder URL in the Terminal request is invalid.");
                return nil;
            }
            [folders addObject:folder];
        } else {
            OITSetError(error, @"The Terminal request contains invalid or duplicate fields.");
            return nil;
        }
    }
    if (![version isEqualToString:@"1"] ||
        (![mode isEqualToString:@"default"] && ![mode isEqualToString:@"new-window"])) {
        OITSetError(error, @"This Terminal request version or action is not supported.");
        return nil;
    }
    return [self requestWithMode:[mode isEqualToString:@"new-window"] ? OITOpenModeNewWindow : OITOpenModeDefault
                     folderURLs:folders error:error];
}
@end
