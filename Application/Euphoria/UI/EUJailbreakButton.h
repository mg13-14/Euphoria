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

@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic) BOOL didExpand;
@property (nonatomic, assign) pthread_mutex_t canStartJailbreak;

- (instancetype)initWithAction:(UIAction *)actions;
- (void)expandButton:(NSArray<NSLayoutConstraint *> *)constraints;

- (void)lockMutex;
- (void)unlockMutex;

@end

NS_ASSUME_NONNULL_END
