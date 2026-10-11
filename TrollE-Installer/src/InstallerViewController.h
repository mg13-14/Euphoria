//
//  InstallerViewController.h
//  TrollE-Installer
//
//  独立安装器最小 UI：选 IPA（文件 App/分享）→引擎选择（B 永久/C 容器）→日志窗。
//  抽离：并行搜索员C，2026-09-03。
//

#import <UIKit/UIKit.h>

@interface InstallerViewController : UIViewController

/// URL scheme 入口（main.m AppDelegate 转发；euphoria-trolle://launch?id=<uuid>）
+ (BOOL)handleOpenURL:(NSURL *)url;

@end
