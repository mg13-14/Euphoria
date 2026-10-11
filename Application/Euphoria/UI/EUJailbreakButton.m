//
//  EUJailbreakButton.m
//  Euphoria
//
//  Created by tomt000 on 13/01/2024.
//

#import "EUJailbreakButton.h"
#import "EUDoubleHelixIndicator.h"
#import "EUUIManager.h"
#import "EUGlobalAppearance.h"
#import "EUThemeManager.h"

@implementation EUJailbreakButton

- (instancetype)initWithAction:(UIAction *)actions
{
    if (self = [super init])
    {
        // P1-F1 深度毛玻璃：主按钮=玻璃卡片（docs/08 §3-1：systemChromeMaterialDark
        // 玻璃底 + 主题染色 + 24pt 连续圆角 + 1px 月白 12% 描边；展开态玻璃淡出见 expandButton）
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = 24;
        self.layer.masksToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        self.glassView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        self.glassView.translatesAutoresizingMaskIntoConstraints = NO;
        self.glassView.userInteractionEnabled = NO;
        [self insertSubview:self.glassView atIndex:0];

        self.glassTintView = [[UIView alloc] init];
        self.glassTintView.backgroundColor = [EUThemeManager menuColorWithAlpha:0.35];
        self.glassTintView.translatesAutoresizingMaskIntoConstraints = NO;
        self.glassTintView.userInteractionEnabled = NO;
        [self insertSubview:self.glassTintView aboveSubview:self.glassView];

        self.glassBorder = [CAShapeLayer layer];
        self.glassBorder.strokeColor = [UIColor colorWithWhite:0.92 alpha:0.12].CGColor; // 月白 12%
        self.glassBorder.fillColor = [UIColor clearColor].CGColor;
        self.glassBorder.lineWidth = 1.0;
        [self.layer addSublayer:self.glassBorder];

        [NSLayoutConstraint activateConstraints:@[
            [self.glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.glassTintView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.glassTintView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.glassTintView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.glassTintView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        self.button = [EUActionMenuButton buttonWithAction:actions chevron:NO];
        [self.button setContentHorizontalAlignment:UIControlContentHorizontalAlignmentCenter];
        self.button.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.button];
        [NSLayoutConstraint activateConstraints:@[
            [self.button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.button.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)expandButton:(NSArray<NSLayoutConstraint *> *)constraints
{
    if (self.didExpand)
        return;

    //We're doing some setup, let's lock the mutex
    [self lockMutex];
        
    self.didExpand = TRUE;

    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    float topPadding = (window.frame.size.height * (1 - 0.74));
    topPadding += 35;
    
    [self setupLog: topPadding];
    [self setupPackageManagerPicker: topPadding];
    
    [NSLayoutConstraint deactivateConstraints:constraints];


    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
        [self.topAnchor constraintEqualToAnchor:window.topAnchor constant:topPadding],
        [self.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:100] // slightly out of the screen to hide corners on i8
    ]];
    
    [self.button setUserInteractionEnabled:NO];

    // P1-F1：展开态=全屏功能容器——玻璃底/染色/描边淡出（全屏模糊过重，log/picker 自带样式）
    [UIView animateWithDuration:0.2 animations:^{
        [self.glassView setAlpha:0.0];
        [self.glassTintView setAlpha:0.0];
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.2];
        self.glassBorder.opacity = 0.0;
        [CATransaction commit];
    }];

    [UIView animateWithDuration: 0.2 animations:^{ [self.button setAlpha:0.0]; }];
    [UIView animateWithDuration:0.75 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        [window layoutIfNeeded];
        [self.button setAlpha:0.0];
    } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self setupTitle];
    });

    if ([[EUUIManager sharedInstance] enabledPackageManagerKeys].count > 0)
    {
        //we can start, unlock the mutex
        [self unlockMutex];
    }

}

- (void)setupLog: (float)topPadding
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    if ([[EUUIManager sharedInstance] isDebug])
        self.logView = [[EUDebugLogView alloc] init];
    else
        self.logView = [[EULyricsLogView alloc] init];
    
    [[EUUIManager sharedInstance] setLogView:self.logView];

    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.logView.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
        [self.logView.topAnchor constraintEqualToAnchor:window.topAnchor constant:topPadding],
        [self.logView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:0]
    ]];

    [window layoutIfNeeded];
}

- (void)setupPackageManagerPicker: (float)topPadding
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    if ([[EUUIManager sharedInstance] enabledPackageManagerKeys].count > 0)
        return;

    self.pkgManagerPickerView = [[EUPkgManagerPickerView alloc] initWithCallback:^(BOOL success) {
        [self.pkgManagerPickerView removeFromSuperview];
        self.logView.hidden = NO;
        [self unlockMutex];
    }];

    self.pkgManagerPickerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.pkgManagerPickerView.alpha = 0.0;

    [self addSubview:self.pkgManagerPickerView];

    [NSLayoutConstraint activateConstraints:@[
       [self.pkgManagerPickerView.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
       [self.pkgManagerPickerView.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
       [self.pkgManagerPickerView.topAnchor constraintEqualToAnchor:window.topAnchor constant:topPadding],
       [self.pkgManagerPickerView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:0]
    ]];
    
    [UIView animateWithDuration:0.25 delay:0.25 options: UIViewAnimationOptionCurveEaseInOut animations:^{
        self.pkgManagerPickerView.alpha = 1.0;
    } completion:nil];

    [window layoutIfNeeded];
}

- (void)setupTitle
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = EULocalizedString(@"Status_Title_Jailbreaking");
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.alpha = 0.0;
    [self addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.centerXAnchor constraintEqualToAnchor:window.centerXAnchor constant:20],
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:20],
    ]];

    [UIView animateWithDuration:0.2 animations:^{
        titleLabel.alpha = 1.0;
    }];

    EUDoubleHelixIndicator *indicator = [[EUDoubleHelixIndicator alloc] init];
    [self addSubview:indicator];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [indicator.trailingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor constant:-10],
        [indicator.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [indicator.widthAnchor constraintEqualToConstant:30],
        [indicator.heightAnchor constraintEqualToConstant:12],
    ]];
}

- (void)setEnabled:(BOOL)enabled
{
    self.button.userInteractionEnabled = enabled;
    if (enabled) {
        self.alpha = 1.0;
    } else {
        self.alpha = 0.7;
    }
}

// P1-F1：描边环贴圆角——布局变化后同步 path（展开动画期间随 bounds 变化）
- (void)layoutSubviews
{
    [super layoutSubviews];
    self.glassBorder.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                   byRoundingCorners:UIRectCornerAllCorners
                                                         cornerRadii:CGSizeMake(24, 24)].CGPath;
}

- (BOOL)isEnabled
{
    return self.button.userInteractionEnabled;
}

#pragma mark - Mutex

-(void)lockMutex
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pthread_mutex_init(&self->_canStartJailbreak, NULL);
    });
    pthread_mutex_lock(&self->_canStartJailbreak);
}

-(void)unlockMutex
{
    pthread_mutex_unlock(&self->_canStartJailbreak);
}

@end
