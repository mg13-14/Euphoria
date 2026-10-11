//
//  main.m
//  TrollE-Installer
//
//  独立安装器入口+AppDelegate（UIKit 最小面；免越狱侧载运行）。
//  抽离：并行搜索员C，2026-09-03。
//  2026-09-05 C 自查修复：main() 原置于 @interface 之前引用
//  InstallerAppDelegate——clang 要求 ObjC 类先声明后使用（用户批评
//  "老是编译错"的实锤之一）。修法=AppDelegate 整体前置，main() 收尾。
//

#import <UIKit/UIKit.h>
#import "InstallerViewController.h"

@interface InstallerAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation InstallerAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UINavigationController alloc]
        initWithRootViewController:[[InstallerViewController alloc] init]];
    [self.window makeKeyAndVisible];
    return YES;
}

// 引擎 C 容器启动接引（euphoria-trolle://launch?id=<uuid>——LC 实证机制；
// 本安装器只处理"容器条目注册在本镜像表"的 launch，本体已装时由本体接管）
- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    return [InstallerViewController handleOpenURL:url];
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([InstallerAppDelegate class]));
    }
}
