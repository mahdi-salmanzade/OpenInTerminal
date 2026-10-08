#import <Foundation/Foundation.h>

@class OITRequest;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const OITTerminalLauncherErrorDomain;

@interface TerminalLauncher : NSObject

/// Call on the main thread. Completion is also delivered on the main thread.
- (void)openRequest:(OITRequest *)request
         completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
