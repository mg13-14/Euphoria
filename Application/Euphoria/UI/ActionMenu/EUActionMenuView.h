//
//  EUActionMenuView.h
//  Euphoria
//
//  Created by tomt000 on 04/01/2024.
//

#import <UIKit/UIKit.h>
#import "EUActionMenuDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface EUActionMenuView : UIView

@property (atomic) UIStackView *buttonsView;
@property (atomic) id<EUActionMenuDelegate> delegate;
@property (nonatomic) NSArray *actions;

- (instancetype)initWithActions:(NSArray<UIAction*> *)actions delegate:(id<EUActionMenuDelegate>)delegate;
- (void)hide;

@end

NS_ASSUME_NONNULL_END
