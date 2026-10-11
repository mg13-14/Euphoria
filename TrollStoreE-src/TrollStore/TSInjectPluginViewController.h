//
//  TSInjectPluginViewController.h
//  TrollStoreE
//
//  注入插件功能（Euphoria 定制）：导入 .ipa/.tipa 安装包 → 选择 .dylib 插件注入 → 重签输出
//  架构：导入(UIDocumentPicker) → 解包(libarchive) → LC_LOAD_DYLIB 注入(Mach-O) → ldid 重签(自带 ldid-ios-kit)
//

#import <UIKit/UIKit.h>

@interface TSInjectPluginViewController : UIViewController
@property (nonatomic, strong) NSString *importedIPAPath;
@end
