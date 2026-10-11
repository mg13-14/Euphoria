//
//  Bootstrapper.h
//  Euphoria
//
//  Created by Lars Fröder on 09.01.24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const bootstrapErrorDomain;
typedef NS_ENUM(NSInteger, BootstrapErrorCode) {
    BootstrapErrorCodeFailedToGetURL            = -1,
    BootstrapErrorCodeFailedToDownload          = -2,
    BootstrapErrorCodeFailedDecompressing       = -3,
    BootstrapErrorCodeFailedExtracting          = -4,
    BootstrapErrorCodeFailedRemount             = -5,
    BootstrapErrorCodeFailedFinalising          = -6,
    BootstrapErrorCodeFailedReplacing           = -7,
};

@interface EUBootstrapper : NSObject <NSURLSessionDelegate, NSURLSessionDownloadDelegate>
{
    NSURLSession *_urlSession;
    NSURLSessionDownloadTask *_bootstrapDownloadTask;
    void (^_downloadCompletionBlock)(NSURL * _Nullable location, NSError * _Nullable error);
}

- (void)prepareBootstrapWithCompletion:(void (^)(NSError *))completion;
- (NSError *)updateVarJbSymlink;
- (NSError *)ensurePrivatePrebootIsWritable;
- (NSError *)installPackageManagers;
- (NSError *)finalizeBootstrap;
- (NSError *)deleteBootstrap;

/// 越狱模式键（SSOT 单点，R25-2/C 2026-09-05）：@"Mode-Rootless"（默认+rootful 复用）
/// 或 @"Mode-Roothide"。源集选择（presetSources）与 ElleKit 变体选择共用此判定。
- (NSString *)bootstrapModeKey;

@end

NS_ASSUME_NONNULL_END
