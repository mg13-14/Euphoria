//
//  EUActionMenuView.m
//  Euphoria
//
//  Created by tomt000 on 04/01/2024.
//

#import "EUActionMenuView.h"
#import "EUActionMenuButton.h"
#import "EUGlobalAppearance.h"
#import "EUThemeManager.h"

@interface EUActionMenuView ()
// P1-F1 深度毛玻璃：玻璃描边层（layoutSubviews 懒建，环贴 24pt 圆角）
@property (nonatomic) CAShapeLayer *glassBorder;
@end

@implementation EUActionMenuView

- (instancetype)initWithActions:(NSArray<UIAction*> *)actions delegate:(id<EUActionMenuDelegate>)delegate
{
    if (self = [super init])
    {
        [self setDelegate:delegate];
        [self setActions:actions];
        // P1-F1 深度毛玻璃：弹出菜单=玻璃卡片（docs/08 §3-1：systemChromeMaterialDark
        // 玻璃底 + 主题染色 + 24pt 连续圆角 + 1px 月白 12% 描边，与主按钮同规格）
        self.backgroundColor = [EUThemeManager menuColorWithAlpha:0.18];
        self.layer.cornerRadius = 24;
        self.layer.masksToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        glass.userInteractionEnabled = NO;
        [self insertSubview:glass atIndex:0];

        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [glass.topAnchor constraintEqualToAnchor:self.topAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

// P1-F1：描边环贴圆角——布局后同步 path
- (void)layoutSubviews
{
    [super layoutSubviews];
    if (self.glassBorder == nil)
    {
        self.glassBorder = [CAShapeLayer layer];
        self.glassBorder.strokeColor = [UIColor colorWithWhite:0.92 alpha:0.12].CGColor; // 月白 12%
        self.glassBorder.fillColor = [UIColor clearColor].CGColor;
        self.glassBorder.lineWidth = 1.0;
        [self.layer addSublayer:self.glassBorder];
    }
    self.glassBorder.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:24].CGPath;
}

- (void)setActions:(NSArray *)actions
{
    _actions = actions;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshStack];
    });
}

-(void)refreshStack
{
    [self.buttonsView removeFromSuperview];
    self.buttonsView = [[UIStackView alloc] init];
    self.buttonsView.axis = UILayoutConstraintAxisVertical;
    self.buttonsView.translatesAutoresizingMaskIntoConstraints = NO;

    int button_height = [EUGlobalAppearance isHomeButtonDevice] ? UI_ACTION_HEIGHT_HOME_BTN : UI_ACTION_HEIGHT;
    if ([EUGlobalAppearance isSmallDevice])
        button_height = UI_ACTION_HEIGHT_TINY;

    [self.actions enumerateObjectsUsingBlock:^(UIAction *action, NSUInteger idx, BOOL *stop) {
        EUActionMenuButton *button = [EUActionMenuButton buttonWithAction:action chevron:[self.delegate actionMenuShowsChevronForAction:action]];
        button.enabled = [self.delegate actionMenuActionIsEnabled:action];
        [button setBottomSeparator:idx != self.actions.count - 1];
        [self.buttonsView addArrangedSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.heightAnchor constraintEqualToConstant:button_height],
            [button.widthAnchor constraintEqualToAnchor:self.buttonsView.widthAnchor]
        ]];
    }];

    [self addSubview:self.buttonsView];

    int inner_padding = [EUGlobalAppearance isSmallDevice] ? UI_INNER_PADDING_TINY : UI_INNER_PADDING;

    [NSLayoutConstraint activateConstraints:@[
        [self.buttonsView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:inner_padding],
        [self.buttonsView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-inner_padding],
        [self.buttonsView.topAnchor constraintEqualToAnchor:self.topAnchor constant:UI_INNER_TOP_PADDING],
        [self.buttonsView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-UI_INNER_TOP_PADDING],
    ]];

}

- (void)hide
{
    [self setUserInteractionEnabled:NO];
    CGAffineTransform transform = CGAffineTransformMakeTranslation(0, -75);
    transform = CGAffineTransformScale(transform, 0.6, 0.6);
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        [self setAlpha:0.0];
        [self setTransform:transform];
    } completion:nil];
}

@end
