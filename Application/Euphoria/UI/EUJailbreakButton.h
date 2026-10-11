//
//  EUJailbreakButton.h
//  Euphoria
//
//  Created by tomt000 on 13/01/2024.
//

#import <UIKit/UIKit.h>
#import "EUActionMenuButton.h"
#import "EULyricsLogView.h"
#import "EUDebugLogView.h"
#import "EUPkgManagerPickerView.h"
#import <pthread.h>

NS_ASSUME_NONNULL_BEGIN

@interface EUJailbreakButton : UIView

@property EUActionMenuButton *button;
@property UIView<EULogViewProtocol> *logView;
@property EUPkgManagerPickerView *pkgManagerPickerView;

// P1-F1 深度毛玻璃（docs/08-仙境风UI设计规范.md §3-1 卡片规格落地）：
@property (nonatomic) UIVisualEffectView *glassView;      // systemChromeMaterialDark 玻璃底
@property (nonatomic) UIView *glassTintView;              // 主题染色叠层（玻璃上保留 Euphoria 紫）
@property (nonatomic) CAShapeLayer *glassBorder;          // 1px 月白 12% 环贴描边

@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic) BOOL didExpand;
@property (nonatomic, assign) pthread_mutex_t canStartJailbreak;

- (instancetype)initWithAction:(UIAction *)actions;
- (void)expandButton:(NSArray<NSLayoutConstraint *> *)constraints;

- (void)lockMutex;
- (void)unlockMutex;

@end

NS_ASSUME_NONNULL_END
