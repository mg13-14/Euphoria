//
//  EUStandaloneEnvironment.h
//  TrollE-Installer
//
//  独立环境层——替代主树 EUEnvironmentManager 的 isJailbroken/runAsRoot（解耦点 #2）。
//  语义边界（与主树差异，如实）：
//   - isJailbroken = /var/jb 符号链接在位探测（只读）
//   - runAsRoot   = getuid()==0 时直接执行；否则失败返回 NO
//     （独立安装器无 launchdhook/electra 通道，不能"借" root——
//       免越狱会话态的 root 由引擎 B 的 17+ 直接内核写入在进程内自取，不经此口）
//  抽离：并行搜索员C，2026-09-03。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^EUStandaloneVoidBlock)(void);

@interface EUStandaloneEnvironment : NSObject

+ (instancetype)sharedEnvironment;

/// 越狱态探测（/var/jb 符号链接存在性，只读）
- (BOOL)isJailbroken;

/// root 执行：getuid()==0 → 直接跑；否则 NO（见头注释语义边界）
- (BOOL)runAsRoot:(EUStandaloneVoidBlock)block;

/// 当前进程 uid（引擎 B 会话 root 化后的自检用）
- (uid_t)currentUID;

@end

NS_ASSUME_NONNULL_END
