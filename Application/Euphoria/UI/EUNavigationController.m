//
//  EUNavigationController.m
//  Euphoria
//
//  Created by tomt000 on 04/01/2024.
//

#import "EUNavigationController.h"
#import <objc/runtime.h>
#import "EUModalBackAction.h"
#import "EUGlobalAppearance.h"
#import "EUThemeManager.h"

@interface EUNavigationController ()

@property (nonatomic) UIImageView *backgroundImageView;
@property (nonatomic) EUMainViewController *mainView;
@property (nonatomic) EUModalBackAction *backAction;

@end

@interface UINavigationController (Private)
-(CGRect)_frameForViewController:(id)arg1;
@end

@implementation EUNavigationController

- (void)viewDidLoad
{
    [self setupBackground];
    [super viewDidLoad];
    [self setNavigationBarHidden:YES];
    [self pushViewController:(self.mainView = [[EUMainViewController alloc] init]) animated:NO];
    [self setDelegate:self];
    [self setOverrideUserInterfaceStyle:UIUserInterfaceStyleDark];
}

- (void)setupBackground
{
    EUTheme *theme = [[EUThemeManager sharedInstance] enabledTheme];
    
    self.view.backgroundColor = [UIColor blackColor];
    self.backgroundImageView = [[UIImageView alloc] init];
    self.backgroundImageView.image = [theme image];
    self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.backgroundImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundImageView.userInteractionEnabled = NO;
    self.backgroundImageView.layer.zPosition = -1;

    [self.view insertSubview:self.backgroundImageView atIndex:0];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backgroundImageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.backgroundImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.backgroundImageView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:-100],
        [self.backgroundImageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:100],
    ]];

    self.backAction = [[EUModalBackAction alloc] initWithAction:^{
        [self popViewControllerAnimated:YES];
    }];
    self.backAction.translatesAutoresizingMaskIntoConstraints = NO;
    self.backAction.hidden = YES;
    
    [self.view insertSubview:self.backAction atIndex:2];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backAction.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.backAction.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.backAction.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.backAction.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setBackgroundDimmed:(BOOL)dimmed
{
    [UIView animateWithDuration:0.3 animations:^{
        self.backgroundImageView.alpha = dimmed ? 0.4 : 1;
    }];
    self.backgroundImageView.userInteractionEnabled = dimmed;
    self.backAction.hidden = !dimmed;
}

#pragma mark - Delegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
           animationControllerForOperation:(UINavigationControllerOperation)operation
                        fromViewController:(UIViewController *)fromVC
                          toViewController:(UIViewController *)toVC {
    
    
    if (fromVC.class == EUMainViewController.class || toVC.class == EUMainViewController.class)
        return [[EUModalTransitionScale alloc] initForwards: operation == UINavigationControllerOperationPush];
    return [[EUModalTransitionPush alloc] initForwards: operation == UINavigationControllerOperationPush];
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    [self setBackgroundDimmed:![viewController isKindOfClass:[EUMainViewController class]]];
    [self.backAction setIgnoreFrame:[self _frameForViewController:viewController]];
}

#pragma mark - Overrides

-(CGRect)_frameForViewController:(id)viewController
{
    CGRect orig = [super _frameForViewController: viewController];
    if ([[viewController class] isEqual: [EUMainViewController class]])
        return orig;
    
    orig.size.width = fmin(orig.size.width - UI_MODAL_PADDING * 2, UI_IPAD_MAX_WIDTH);
    orig.size.height *= [EUGlobalAppearance isSmallDevice] ? 0.8 : 0.7;
    orig.origin.x = (self.view.frame.size.width - orig.size.width) / 2;
    orig.origin.y = (self.view.frame.size.height - orig.size.height) / 2;

    return orig;

}


@end
