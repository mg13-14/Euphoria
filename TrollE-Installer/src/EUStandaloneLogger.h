//
//  EUStandaloneLogger.h/.m
//  TrollE-Installer
//
//  独立日志层——替代主树 EUUIManager.sendLog（解耦点 #1）。
//  双通道：NSLog（Xcode/Console.app 可见）+ UI 回调（InstallerViewController 注册渲染）。
//  抽离：并行搜索员C，2026-09-03。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EUStandaloneLogger : NSObject

/// UI 侧注册回调（主线程派发；线程安全）
@property (nonatomic, copy, nullable) void (^onLog)(NSString *line);

+ (instancetype)sharedLogger;

/// 独立版日志入口（替代主树 EUTrolleLog 宏的落点）
- (void)log:(NSString *)fmt, ...;

/// debug 级（当前与 info 同通道，保留主树宏签名兼容）
- (void)logDebug:(NSString *)fmt, ...;

@end

NS_ASSUME_NONNULL_END
