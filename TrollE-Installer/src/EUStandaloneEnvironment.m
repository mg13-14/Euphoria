//
//  EUStandaloneEnvironment.m
//  TrollE-Installer
//
//  抽离：并行搜索员C，2026-09-03（解耦点 #2）
//

#import "EUStandaloneEnvironment.h"
#import <sys/stat.h>
#import <unistd.h>

@implementation EUStandaloneEnvironment

+ (instancetype)sharedEnvironment
{
    static EUStandaloneEnvironment *env = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ env = [[self alloc] init]; });
    return env;
}

- (BOOL)isJailbroken
{
    // rootless 布局：/var/jb 为符号链接（ARCHITECTURE.md §关键设计模式1），
    // 存在即越狱态（只读探测，独立安装器不做任何越狱态写入）
    struct stat st;
    return lstat("/var/jb", &st) == 0 && S_ISLNK(st.st_mode);
}

- (BOOL)runAsRoot:(EUStandaloneVoidBlock)block
{
    if (!block) return NO;
    if (getuid() != 0) return NO; // 语义边界：无通道借 root，见头注释
    block();
    return YES;
}

- (uid_t)currentUID
{
    return getuid();
}

@end
