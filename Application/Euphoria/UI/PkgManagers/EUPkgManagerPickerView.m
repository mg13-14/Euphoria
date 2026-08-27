//
//  EUPkgManagerPickerView.m
//  Euphoria
//
//  Created by tomt000 on 08/02/2024.
//

#import "EUPkgManagerPickerView.h"
#import "EUAppSwitch.h"
#import "EUUIManager.h"
#import "EUActionMenuButton.h"
#import "EUGlobalAppearance.h"

@interface EUPkgManagerPickerView ()

@property (nonatomic, retain) EUActionMenuButton *continueAction;

@end

#define PADDING_BTN_CONTINUE 30

@implementation EUPkgManagerPickerView

-(id)initWithCallback:(void (^)(BOOL))callback {
    self = [super init];
    if (self) {
        UIStackView *switchStack = [[UIStackView alloc] init];
        switchStack.axis = UILayoutConstraintAxisHorizontal;
        switchStack.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:switchStack];

        [NSLayoutConstraint activateConstraints:@[
            [switchStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [switchStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant: -([EUGlobalAppearance isHomeButtonDevice] ? 0 : 10)]
        ]];

        NSArray *packageManagers = [[EUUIManager sharedInstance] availablePackageManagers];
        [packageManagers enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *manager = (NSDictionary *)obj;
            EUAppSwitch *appSwitch = [[EUAppSwitch alloc] initWithIcon:[UIImage imageNamed:manager[@"Icon"]] title:manager[@"Display Name"]];
            appSwitch.selected = [[[EUUIManager sharedInstance] enabledPackageManagerKeys] containsObject:manager[@"Key"]];
            appSwitch.onSwitch = ^(BOOL enabled) {
                [[EUUIManager sharedInstance] setPackageManager:manager[@"Key"] enabled:enabled];
                [self updateButtonState];
            };

            appSwitch.translatesAutoresizingMaskIntoConstraints = NO;
            [switchStack addArrangedSubview:appSwitch];

            [NSLayoutConstraint activateConstraints:@[
                [appSwitch.widthAnchor constraintEqualToConstant:110],
                [appSwitch.heightAnchor constraintEqualToConstant:110]
            ]];
        }];
        

        UILabel *title = [[UILabel alloc] init];
        title.text = EULocalizedString(@"Status_Title_Select_Package_Managers");
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightMedium];
        title.textAlignment = NSTextAlignmentCenter;
        title.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:title];

        [NSLayoutConstraint activateConstraints:@[
            [title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [title.bottomAnchor constraintEqualToAnchor:switchStack.topAnchor constant:-30]
        ]];
        
        UILabel *tooltip = [[UILabel alloc] init];
        tooltip.text = EULocalizedString(@"Select_Package_Managers_Install_Message");
        tooltip.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
        tooltip.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        tooltip.textAlignment = NSTextAlignmentCenter;
        tooltip.numberOfLines = 3;
        tooltip.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:tooltip];

        [NSLayoutConstraint activateConstraints:@[
            [tooltip.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [tooltip.topAnchor constraintEqualToAnchor:switchStack.bottomAnchor constant:15],
            [tooltip.widthAnchor constraintEqualToAnchor:switchStack.widthAnchor multiplier:1.25]
        ]];
        
        self.continueAction = [EUActionMenuButton buttonWithAction:[UIAction actionWithTitle:EULocalizedString(@"Continue") image:[UIImage systemImageNamed:@"arrow.right" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"continue" handler:^(__kindof UIAction * _Nonnull action) {
            callback(TRUE);
        }] chevron:NO];
        self.continueAction.layer.cornerRadius = 14.0;
        self.continueAction.layer.cornerCurve = kCACornerCurveContinuous;
        self.continueAction.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        self.continueAction.translatesAutoresizingMaskIntoConstraints = NO;
        
        [self addSubview:self.continueAction];

        
        [NSLayoutConstraint activateConstraints:@[
            [self.continueAction.heightAnchor constraintEqualToConstant:50],
            [self.continueAction.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PADDING_BTN_CONTINUE - ([EUGlobalAppearance isHomeButtonDevice] ? 0 : 10)],
            [self.continueAction.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PADDING_BTN_CONTINUE],
            [self.continueAction.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PADDING_BTN_CONTINUE]
        ]];
        
        
        
        [self updateButtonState];
        
    }
    return self;
}

- (void)updateButtonState
{
    NSArray *selected = [[EUUIManager sharedInstance] enabledPackageManagerKeys];
    self.continueAction.enabled = selected.count > 0;
    self.continueAction.backgroundColor = [UIColor colorWithWhite:1.0 alpha:selected.count > 0 ? 0.2 : 0.1];
}

@end
