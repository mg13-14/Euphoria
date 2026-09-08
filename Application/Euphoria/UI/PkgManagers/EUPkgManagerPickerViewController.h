//
//  EUPkgManagerPickerViewController.h
//  Euphoria
//
//  Created by tomt000 on 11/02/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface EUPkgManagerPickerViewController : UIViewController

@end

/// EPM（自研包管理器·T18 契约 v1）内嵌页：已装包清单浏览+刷新。
/// v1 诚实边界：安装/升级/搜索=下批；未越狱态进入=诚实提示。
/// 实现在 EUPkgManagerPickerViewController.m（C 2026-09-05 落码）。
@interface EUPMPackagesViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
