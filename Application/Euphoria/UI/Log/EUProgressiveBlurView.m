//
//  EUProgressiveBlurView.m
//  Euphoria
//
//  Created by tomt000 on 18/01/2024.
//

#import "EUProgressiveBlurView.h"

@interface UIBlurEffect (Private)
- (id)effectSettings;
@end
@interface EUBlurEffect : UIBlurEffect
@end
@implementation EUBlurEffect
- (id)effectSettings {
    id settings = [super effectSettings];
    [settings setValue:@(1.0) forKey:@"scale"];
    [settings setValue:@0 forKey:@"grayscaleTintAlpha"];
    [settings setValue:@1 forKey:@"saturationDeltaFactor"];
    return settings;
}

@end

@interface EUProgressiveBlurView ()

@property (retain) id variableBlur;

@end

@implementation EUProgressiveBlurView

- (instancetype)initWithGradientMask:(UIImage *)gradientMask maxBlurRadius:(CGFloat)maxBlurRadius {
    self = [super initWithEffect:[EUBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
    if (self) {
        Class CAFilter = NSClassFromString(@"CAFilter");
        self.variableBlur = [CAFilter performSelector:NSSelectorFromString(@"filterWithType:") withObject:@"variableBlur"];
        [self.variableBlur setValue:@(maxBlurRadius) forKey:@"inputRadius"];
        [self.variableBlur setValue:(__bridge id)(gradientMask.CGImage) forKey:@"inputMaskImage"];
        [self.variableBlur setValue:@YES forKey:@"inputNormalizeEdges"];
    }
    return self;
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    [self.subviews.firstObject.layer setValue:@[self.variableBlur] forKey:@"filters"];
}

@end
