#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OITOpenMode) {
    OITOpenModeDefault = 0,
    OITOpenModeNewWindow = 1,
};

/// A small, validated message from the Finder extension to its containing app.
@interface OITRequest : NSObject
@property(nonatomic, readonly) OITOpenMode mode;
@property(nonatomic, copy, readonly) NSArray<NSURL *> *folderURLs;
@property(nonatomic, copy, readonly) NSURL *URL;
+ (nullable instancetype)requestWithMode:(OITOpenMode)mode
                             folderURLs:(NSArray<NSURL *> *)folderURLs
                                  error:(NSError **)error;
+ (nullable instancetype)requestFromURL:(NSURL *)URL error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
