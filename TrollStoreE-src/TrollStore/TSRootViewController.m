#import "TSRootViewController.h"
#import "TSAppTableViewController.h"
#import "TSSettingsListController.h"
#import "TSInjectPluginViewController.h"
#import "TSIpaEditorViewController.h"
#import <TSPresentationDelegate.h>

@implementation TSRootViewController

- (void)loadView {
        [super loadView];

        TSAppTableViewController* appTableVC = [[TSAppTableViewController alloc] init];
        appTableVC.title = @"应用";

        TSSettingsListController* settingsListVC = [[TSSettingsListController alloc] init];
        settingsListVC.title = @"设置";

        // Euphoria 定制：底部工具栏新增「注入插件」「修改安装包」两个功能页
        TSInjectPluginViewController* injectVC = [[TSInjectPluginViewController alloc] init];
        injectVC.title = @"注入插件";

        TSIpaEditorViewController* ipaEditorVC = [[TSIpaEditorViewController alloc] init];
        ipaEditorVC.title = @"修改安装包";

        UINavigationController* appNavigationController = [[UINavigationController alloc] initWithRootViewController:appTableVC];
        UINavigationController* settingsNavigationController = [[UINavigationController alloc] initWithRootViewController:settingsListVC];
        UINavigationController* injectNavigationController = [[UINavigationController alloc] initWithRootViewController:injectVC];
        UINavigationController* ipaEditorNavigationController = [[UINavigationController alloc] initWithRootViewController:ipaEditorVC];
        
        appNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"square.stack.3d.up.fill"];
        settingsNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"gear"];
        injectNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"syringe.fill"];
        ipaEditorNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"wand.and.stars"];

        self.title = @"Root View Controller";
        self.viewControllers = @[appNavigationController, injectNavigationController, ipaEditorNavigationController, settingsNavigationController];
}

- (void)viewDidLoad
{
        [super viewDidLoad];

        TSPresentationDelegate.presentationViewController = self;
}

@end
