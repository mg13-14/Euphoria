//
//  EUFairyStyle.m
//  TrollE-Installer
//
//  仙境风 UI 工具集实现（08 规范 §1–§4）。全 CA 原生零依赖。
//  B 线 2026-09-05。
//

#import "EUFairyStyle.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// 涟漪清道夫（CAAnimation delegate 持有环规避：单例，动画结束移除 ring 层）
@interface EUFairyRippleCleanup : NSObject <CAAnimationDelegate>
+ (instancetype)sharedCleanup;
@end

static UIColor *EUFairyHex(uint32_t hex, CGFloat alpha)
{
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

#pragma mark - UIButton 按压反馈（分类私有）

@interface UIButton (EUFairyPress)
- (void)eufairy_touchDown;
- (void)eufairy_touchUp;
@end

static void EUFairySetPress(UIButton *b, BOOL pressed)
{
    [UIView animateWithDuration:pressed ? 0.12 : 0.28
                          delay:0
         usingSpringWithDamping:0.6
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ b.transform = pressed ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity; }
                     completion:nil];
}

@implementation UIButton (EUFairyPress)
- (void)eufairy_touchDown { EUFairySetPress(self, YES); }
- (void)eufairy_touchUp   { EUFairySetPress(self, NO); }
@end

@implementation EUFairyRippleCleanup
+ (instancetype)sharedCleanup
{
    static EUFairyRippleCleanup *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    CALayer *ring = [anim valueForKey:@"ringLayer"];
    [ring removeFromSuperlayer];
}
@end

@implementation EUFairyStyle

#pragma mark - §2 色板

+ (UIColor *)colorSuccess        { return EUFairyHex(0x5CE8B5, 1.0); }
+ (UIColor *)colorWarning        { return EUFairyHex(0xFFB86B, 1.0); }
+ (UIColor *)colorDanger         { return EUFairyHex(0xFF6B9D, 1.0); }
+ (UIColor *)colorAurora         { return EUFairyHex(0x8A7CFF, 1.0); }
+ (UIColor *)colorPulse          { return EUFairyHex(0xB47CFF, 1.0); }
+ (UIColor *)colorMoonWhite      { return EUFairyHex(0xEAEAF2, 1.0); }
+ (UIColor *)colorMoonWhiteDim   { return EUFairyHex(0xEAEAF2, 0.6); }

+ (UIFont *)monospaceFontOfSize:(CGFloat)size
{
    UIFont *f = [UIFont fontWithName:@"SFMono-Regular" size:size];
    if (!f) f = [UIFont fontWithName:@"Menlo" size:size];
    if (!f) f = [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
    return f;
}

#pragma mark - §2 深空底色

+ (CAGradientLayer *)deepSpaceBackgroundInView:(UIView *)view
{
    CAGradientLayer *bg = [CAGradientLayer layer];
    bg.name = @"deepSpace";
    bg.colors = @[
        (id)EUFairyHex(0x0B0E2A, 1.0).CGColor,
        (id)EUFairyHex(0x1B1443, 1.0).CGColor,
        (id)EUFairyHex(0x2E1B5E, 1.0).CGColor,
    ];
    bg.locations = @[@0.0, @0.55, @1.0];
    bg.startPoint = CGPointMake(0.5, 0.0);
    bg.endPoint = CGPointMake(0.5, 1.0);
    bg.frame = view.bounds;
    [view.layer insertSublayer:bg atIndex:0];
    return bg;
}

#pragma mark - §4-1 星尘粒子（ReduceMotion 降级）

+ (nullable CAEmitterLayer *)stardustLayerInView:(UIView *)view
{
    if (UIAccessibilityIsReduceMotionEnabled()) return nil; // §4 无障碍：关粒子

    // 1.5pt 月白 60% 圆点粒子贴图（3x 渲染保证锐利）
    CGFloat dotSide = 4.5; // 1.5pt × 3x
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(dotSide, dotSide)];
    UIImage *dot = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextSetFillColorWithColor(c, EUFairyHex(0xEAEAF2, 0.6).CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(0, 0, dotSide, dotSide));
    }];

    CAEmitterLayer *emitter = [CAEmitterLayer layer];
    emitter.name = @"stardust";
    emitter.emitterPosition = CGPointMake(view.bounds.size.width / 2.0, view.bounds.size.height + 10);
    emitter.emitterSize = CGSizeMake(view.bounds.size.width, 1);
    emitter.emitterShape = kCAEmitterLayerLine;
    emitter.renderMode = kCAEmitterLayerOldestFirst;

    CAEmitterCell *cell = [CAEmitterCell emitterCell]; // 修复：类方法为 emitterCell（[CAEmitterCell cell] 不存在）
    cell.contents = (__bridge id)dot.CGImage;
    cell.birthRate = 12;      // §4-1 密度 12/s
    cell.lifetime = 6;
    cell.velocity = 12;       // 缓慢上升
    cell.velocityRange = 4;
    cell.emissionLongitude = (CGFloat)(M_PI / 2.0);  // 竖直向上
    cell.emissionRange = (CGFloat)M_PI / 8.0;        // 轻微左右锥形漂移
    cell.spinRange = (CGFloat)M_PI;
    cell.scale = 1.0;
    cell.scaleRange = 0.3;
    cell.alphaRange = 0.4;
    emitter.emitterCells = @[cell];

    [view.layer addSublayer:emitter];
    return emitter;
}

#pragma mark - §3-2 极光按钮（渐变+流光+按压）

+ (void)styleAuroraButton:(UIButton *)button installing:(BOOL)installing
{
    button.clipsToBounds = YES;
    button.layer.cornerRadius = 16;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [button setTitleColor:EUFairyHex(0x0B0E2A, 0.95) forState:UIControlStateNormal]; // 深字浮于极光
    [button setTitleColor:EUFairyHex(0x0B0E2A, 0.4) forState:UIControlStateDisabled];

    // 极光横向三段（§2）；幂等：重复调用先移除旧渐变层
    for (CALayer *l in button.layer.sublayers.copy) {
        if ([l.name isEqualToString:@"aurora"]) [l removeFromSuperlayer];
    }
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.name = @"aurora";
    grad.colors = @[
        (id)EUFairyHex(0x7CF3D0, 1.0).CGColor,
        (id)EUFairyHex(0x5E8BFF, 1.0).CGColor,
        (id)EUFairyHex(0xB47CFF, 1.0).CGColor,
    ];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint = CGPointMake(1, 0.5);
    [button.layer insertSublayer:grad atIndex:0];

    // 流光：locations 循环平移（3s；ReduceMotion 关动画保留静态渐变，§4）
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *flow = [CABasicAnimation animationWithKeyPath:@"locations"];
        flow.fromValue = @[@(-0.6), @0.0, @0.4];
        flow.toValue = @[@0.6, @1.0, @1.6];
        flow.duration = 3.0;
        flow.repeatCount = HUGE_VALF;
        [grad addAnimation:flow forKey:@"auroraFlow"];
    }

    // installing 脉冲（§5 安装中：紫光脉冲）——opacity 呼吸
    [button.layer removeAnimationForKey:@"installPulse"];
    if (installing && !UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @0.75;
        pulse.toValue = @1.0;
        pulse.duration = 1.2;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [button.layer addAnimation:pulse forKey:@"installPulse"];
    }

    [button addTarget:button action:@selector(eufairy_touchDown) forControlEvents:UIControlEventTouchDown];
    [button addTarget:button action:@selector(eufairy_touchUp)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

+ (void)styleSecondaryButton:(UIButton *)button installing:(BOOL)installing
{
    button.clipsToBounds = YES;
    button.layer.cornerRadius = 16;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [button setTitleColor:[EUFairyStyle colorMoonWhite] forState:UIControlStateNormal];
    [button setTitleColor:EUFairyHex(0xEAEAF2, 0.3) forState:UIControlStateDisabled];
    button.backgroundColor = EUFairyHex(0x1B1443, 0.55); // 深空半透玻璃面
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = EUFairyHex(0xEAEAF2, 0.12).CGColor; // 月白 12% 描边
    [button addTarget:button action:@selector(eufairy_touchDown) forControlEvents:UIControlEventTouchDown];
    [button addTarget:button action:@selector(eufairy_touchUp)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    (void)installing;
}

#pragma mark - §3-1 毛玻璃卡片

+ (UIView *)glassCard
{
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 24;
    card.backgroundColor = EUFairyHex(0x1B1443, 0.85); // §4 降级底：blur 不可用时即纯色

    if (@available(iOS 13.0, *)) {
        UIVisualEffectView *blur = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        blur.translatesAutoresizingMaskIntoConstraints = NO;
        blur.layer.cornerRadius = 24;
        blur.clipsToBounds = YES;
        [card addSubview:blur];
        [NSLayoutConstraint activateConstraints:@[
            [blur.topAnchor constraintEqualToAnchor:card.topAnchor],
            [blur.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
            [blur.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [blur.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        ]];
    }

    // 1px 月白 12% 描边（环贴圆角，布局时调 frame/需在 wrapper 内）
    // 注：描边层 frame 由调用方卡片布局后置（layoutBorderForView: 辅助）
    return card;
}

/// 卡片描边布局辅助（调用方在布局完成后调用；内部建 CAShapeLayer 环贴圆角）
+ (CAShapeLayer *)attachBorderToView:(UIView *)view
{
    CAShapeLayer *border = [CAShapeLayer layer];
    border.name = @"glassBorder";
    border.strokeColor = EUFairyHex(0xEAEAF2, 0.12).CGColor;
    border.fillColor = [UIColor clearColor].CGColor;
    border.lineWidth = 1.0;
    [view.layer addSublayer:border];
    return border;
}

#pragma mark - §3-3 状态徽标点

+ (UIView *)statusDotWithColor:(UIColor *)color
{
    UIView *dot = [[UIView alloc] init];
    dot.backgroundColor = color;
    dot.layer.cornerRadius = 4; // 8pt 圆
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [dot.widthAnchor constraintEqualToConstant:8].active = YES;
    [dot.heightAnchor constraintEqualToConstant:8].active = YES;

    // 呼吸光晕：shadowRadius 4→10 循环 2.4s（ReduceMotion 关，静态光晕保留）
    dot.layer.shadowColor = color.CGColor;
    dot.layer.shadowOpacity = 0.4;
    dot.layer.shadowOffset = CGSizeMake(0, 0);
    dot.layer.shadowRadius = 4;
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *breath = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
        breath.fromValue = @4;
        breath.toValue = @10;
        breath.duration = 2.4;
        breath.autoreverses = YES;
        breath.repeatCount = HUGE_VALF;
        breath.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [dot.layer addAnimation:breath forKey:@"breath"];
    }
    return dot;
}

#pragma mark - §4-3 成功涟漪

+ (void)rippleFromView:(UIView *)sourceView
{
    if (UIAccessibilityIsReduceMotionEnabled()) return; // §4：关涟漪

    UIView *host = sourceView.superview ?: sourceView;
    CGPoint center = CGPointMake(CGRectGetMidX(sourceView.frame), CGRectGetMidY(sourceView.frame));

    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.strokeColor = EUFairyHex(0xEAEAF2, 0.12).CGColor;
    ring.fillColor = [UIColor clearColor].CGColor;
    ring.lineWidth = 1.5;
    ring.path = [UIBezierPath bezierPathWithArcCenter:center radius:8
                                           startAngle:0 endAngle:(CGFloat)(2 * M_PI) clockwise:YES].CGPath;
    [host.layer addSublayer:ring];

    CABasicAnimation *expand = [CABasicAnimation animationWithKeyPath:@"path"];
    UIBezierPath *bigPath = [UIBezierPath bezierPathWithArcCenter:center radius:120
                                                      startAngle:0 endAngle:(CGFloat)(2 * M_PI) clockwise:YES];
    expand.toValue = (id)bigPath.CGPath;
    expand.duration = 1.2;
    expand.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1.0;
    fade.toValue = @0.0;
    fade.duration = 1.2;

    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[expand, fade];
    group.duration = 1.2;
    group.removedOnCompletion = NO;
    group.fillMode = kCAFillModeForwards;
    group.delegate = [EUFairyRippleCleanup sharedCleanup];
    [group setValue:ring forKey:@"ringLayer"];
    [ring addAnimation:group forKey:@"ripple"];
}

@end
