//
//  TSHRootViewController.m
//  EUTrollHelper —— 巨魔E安装器（基于 opa334dev TrollHelper 2.1.1 改进，MIT）
//
//  Euphoria 定制：
//   - 全中文界面
//   - 越狱信任态秒装 TrollStoreE（EUTrustBridge → libjailbreak 信任缓存）
//   - 免越狱时回落原 TrollHelper 安装通道
//

#import "TSHRootViewController.h"
#import "EUTrustBridge.h"
#import <TSUtil.h>
#import <TSPresentationDelegate.h>
#import <UIKit/UIKit.h>

@implementation TSHRootViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	TSPresentationDelegate.presentationViewController = self;
	self.title = @"巨魔E安装器";
}

- (void)loadView
{
	[super loadView];

	UIView *wrap = [[UIView alloc] init];
	wrap.backgroundColor = [UIColor secondarySystemBackgroundColor];

	UILabel *title = [[UILabel alloc] init];
	title.text = @"🧙 巨魔E安装器";
	title.font = [UIFont boldSystemFontOfSize:26];
	title.textAlignment = NSTextAlignmentCenter;
	title.translatesAutoresizingMaskIntoConstraints = NO;

	UILabel *status = [[UILabel alloc] init];
	status.numberOfLines = 0;
	status.textAlignment = NSTextAlignmentCenter;
	status.font = [UIFont systemFontOfSize:13];
	status.textColor = [UIColor secondaryLabelColor];
	status.text = [EUTrustBridge isJailbrokenTrusted]
		? @"当前：越狱信任态（可秒装）"
		: @"当前：未越狱（需先越狱或走免越狱通道）";
	status.translatesAutoresizingMaskIntoConstraints = NO;

	UIButton *installBtn = [UIButton buttonWithType:UIButtonTypeSystem];
	[installBtn setTitle:@"安装巨魔E（信任态秒装）" forState:UIControlStateNormal];
	[installBtn.titleLabel setFont:[UIFont boldSystemFontOfSize:17]];
	[installBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[installBtn addTarget:self action:@selector(installPressed:) forControlEvents:UIControlEventTouchUpInside];
	installBtn.backgroundColor = [UIColor colorWithRed:0.55 green:0.36 blue:0.96 alpha:1];
	installBtn.layer.cornerRadius = 14;
	installBtn.translatesAutoresizingMaskIntoConstraints = NO;

	UIButton *uninstallBtn = [UIButton buttonWithType:UIButtonTypeSystem];
	[uninstallBtn setTitle:@"卸载巨魔E" forState:UIControlStateNormal];
	[uninstallBtn addTarget:self action:@selector(uninstallPressed:) forControlEvents:UIControlEventTouchUpInside];
	uninstallBtn.layer.cornerRadius = 14;
	uninstallBtn.translatesAutoresizingMaskIntoConstraints = NO;

	UILabel *credits = [[UILabel alloc] init];
	credits.numberOfLines = 0;
	credits.font = [UIFont footnoteFont];
	credits.textColor = [UIColor tertiaryLabelColor];
	credits.textAlignment = NSTextAlignmentCenter;
	credits.text = @"上游：TrollHelper 2.1.1（opa334dev，MIT）改进版\n引擎：libjailbreak 信任缓存 · Euphoria 团队";
	credits.translatesAutoresizingMaskIntoConstraints = NO;

	[wrap addSubview:title]; [wrap addSubview:status];
	[wrap addSubview:installBtn]; [wrap addSubview:uninstallBtn]; [wrap addSubview:credits];
	self.view = wrap;

	[NSLayoutConstraint activateConstraints:@[
		[title.topAnchor constraintEqualToAnchor:wrap.safeAreaLayoutGuide.topAnchor constant:48],
		[title.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
		[status.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
		[status.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:20],
		[status.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-20],
		[installBtn.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:32],
		[installBtn.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
		[installBtn.widthAnchor constraintEqualToConstant:280],
		[installBtn.heightAnchor constraintEqualToConstant:50],
		[uninstallBtn.topAnchor constraintEqualToAnchor:installBtn.bottomAnchor constant:14],
		[uninstallBtn.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
		[uninstallBtn.widthAnchor constraintEqualToConstant:280],
		[uninstallBtn.heightAnchor constraintEqualToConstant:44],
		[credits.bottomAnchor constraintEqualToAnchor:wrap.safeAreaLayoutGuide.bottomAnchor constant:-20],
		[credits.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:20],
		[credits.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-20],
	]];
}

- (void)installPressed:(id)sender
{
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"秒装中" message:nil preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:ac animated:YES completion:nil];
	[EUTrustBridge installEmbeddedTrollStoreE:^(BOOL ok, NSString *msg) {
		[ac dismissViewControllerAnimated:YES completion:^{
			UIAlertController *done = [UIAlertController alertControllerWithTitle:ok ? @"完成" : @"失败" message:msg preferredStyle:UIAlertControllerStyleAlert];
			[done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
			[self presentViewController:done animated:YES completion:nil];
		}];
	}];
}

- (void)uninstallPressed:(id)sender
{
	[EUTrustBridge uninstallTrollStoreE:^(BOOL ok, NSString *msg) {
		UIAlertController *done = [UIAlertController alertControllerWithTitle:ok ? @"完成" : @"提示" message:msg preferredStyle:UIAlertControllerStyleAlert];
		[done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:done animated:YES completion:nil];
	}];
}

@end
