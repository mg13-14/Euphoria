//
//  EUStandaloneConfig.m
//  TrollE-Installer
//
//  独立配置实现（解耦点 #4/#5 的落点）。
//  抽离：并行搜索员C，2026-09-03。
//

#import "EUStandaloneConfig.h"
#import <sys/stat.h>

NSString *const EUStandaloneBundleID = @"dev.euphoria.trolle-installer";
NSString *const EUStandaloneURLScheme = @"euphoria-trolle";

NSString *EUStandaloneSandboxRegistryPath(void)
{
    // 独立安装器免越狱态的唯一注册表（条目结构与主树镜像表一致→L1→L3 升级闭环兼容）
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/EUTrollE"]
            stringByAppendingPathComponent:@"registry.plist"];
}

NSString *EUStandaloneMainRegistryPath(void)
{
    // 只读兼容：越狱态主表（独立安装器永不写入）
    return [NSString stringWithFormat:@"%@/var/db/euphoria/trolle.plist",
            EUStandaloneJailbreakRootPath()];
}

NSString *EUStandaloneJailbreakRootPath(void)
{
    // rootless 布局：/var/jb 符号链接在位=越狱态（只读探测；免越狱返回空串）
    struct stat st;
    if (lstat("/var/jb", &st) == 0 && S_ISLNK(st.st_mode)) return @"/var/jb";
    return @"";
}
