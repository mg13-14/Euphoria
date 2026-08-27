//
//  EUProgressiveBlurView.h
//  Euphoria
//
//  Created by tomt000 on 18/01/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface EUProgressiveBlurView : UIVisualEffectView

- (instancetype)initWithGradientMask:(UIImage *)gradientMask maxBlurRadius:(CGFloat)maxBlurRadius;

@end

NS_ASSUME_NONNULL_END
