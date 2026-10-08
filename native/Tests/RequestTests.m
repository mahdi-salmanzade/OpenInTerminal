#import <Foundation/Foundation.h>
#import "OITRequest.h"

static NSUInteger checks = 0;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static NSURL *RequestURL(NSString *mode, NSArray<NSURL *> *folders) {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"openinterminal-app";
    components.host = @"open";
    NSMutableArray *items = [NSMutableArray arrayWithObjects:
        [NSURLQueryItem queryItemWithName:@"version" value:@"1"],
        [NSURLQueryItem queryItemWithName:@"mode" value:mode], nil];
    for (NSURL *folder in folders) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"folder" value:folder.absoluteString]];
    }
    components.queryItems = items;
    return components.URL;
}

int main(void) {
    @autoreleasepool {
        NSFileManager *manager = NSFileManager.defaultManager;
        NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:[@"oit-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]]
                                isDirectory:YES];
        NSError *error = nil;
        Check([manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error],
              @"create test directory");
        @try {
            NSMutableArray<NSURL *> *folders = [NSMutableArray array];
            for (NSString *name in @[@"Spaces and 'quotes'", @"日本語 café 📁", @"line\none",
                                      @"$(touch INJECTED); `echo code`", @"% & + # ?", @"-n"]) {
                NSURL *folder = [root URLByAppendingPathComponent:name isDirectory:YES];
                Check([manager createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:nil error:&error],
                      @"create special-name directory");
                [folders addObject:folder];
            }
            for (NSNumber *modeValue in @[@(OITOpenModeDefault), @(OITOpenModeNewWindow)]) {
                OITRequest *original = [OITRequest requestWithMode:modeValue.integerValue folderURLs:folders error:&error];
                Check(original != nil, @"encode both action modes");
                OITRequest *decoded = [OITRequest requestFromURL:original.URL error:&error];
                Check(decoded != nil && decoded.mode == modeValue.integerValue, @"decode action mode");
                Check([decoded.folderURLs isEqualToArray:folders], @"preserve every filename byte through the request");
            }
            OITRequest *deduplicated = [OITRequest requestWithMode:OITOpenModeDefault
                folderURLs:@[folders[0], folders[0], folders[1]] error:&error];
            Check(deduplicated.folderURLs.count == 2, @"deduplicate selections");
            Check([OITRequest requestWithMode:99 folderURLs:folders error:&error] == nil, @"reject invalid enum");
            Check([OITRequest requestWithMode:0 folderURLs:@[] error:&error] == nil, @"reject empty selection");

            NSURL *file = [root URLByAppendingPathComponent:@"not-a-folder.command"];
            [@"touch SHOULD_NOT_RUN" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
            NSArray *badURLs = @[
                file, [root URLByAppendingPathComponent:@"missing"],
                [NSURL URLWithString:@"https://example.com/folder"],
                [NSURL URLWithString:@"file://remote.invalid/tmp/"],
                [NSURL URLWithString:@"relative/folder"],
            ];
            for (NSURL *badURL in badURLs) {
                Check([OITRequest requestFromURL:RequestURL(@"default", @[badURL]) error:&error] == nil,
                      @"reject non-folder and nonlocal inputs");
            }
            NSString *valid = RequestURL(@"default", @[folders[0]]).absoluteString;
            for (NSString *invalid in @[
                [valid stringByReplacingOccurrencesOfString:@"openinterminal-app:" withString:@"https:"],
                [valid stringByReplacingOccurrencesOfString:@"//open?" withString:@"//other?"],
                [valid stringByAppendingString:@"&mode=new-window"],
                [valid stringByAppendingString:@"&version=1"],
                [valid stringByAppendingString:@"&command=touch"],
                [valid stringByAppendingString:@"#fragment"],
                [valid stringByReplacingOccurrencesOfString:@"version=1" withString:@"version=2"],
                [valid stringByReplacingOccurrencesOfString:@"mode=default" withString:@"mode=execute"],
            ]) {
                Check([OITRequest requestFromURL:[NSURL URLWithString:invalid] error:&error] == nil,
                      @"reject malformed, duplicate, or unsupported request fields");
            }
            Check([OITRequest requestFromURL:RequestURL(@"default", @[folders[0], file]) error:&error] == nil,
                  @"reject whole mixed folder/file request");
            NSMutableArray *tooMany = [NSMutableArray array];
            for (NSUInteger i = 0; i < 129; i++) [tooMany addObject:folders[0]];
            Check([OITRequest requestWithMode:0 folderURLs:tooMany error:&error] == nil, @"bound request size");
            [manager removeItemAtURL:folders[0] error:&error];
            Check([OITRequest requestFromURL:[NSURL URLWithString:valid] error:&error] == nil,
                  @"revalidate deleted folders at action time");
            Check(![manager fileExistsAtPath:[[root URLByAppendingPathComponent:@"INJECTED"] path]],
                  @"request data never executes as shell code");
        } @finally {
            [manager removeItemAtURL:root error:nil];
        }
        printf("Passed %lu native request checks.\n", (unsigned long)checks);
    }
    return 0;
}
