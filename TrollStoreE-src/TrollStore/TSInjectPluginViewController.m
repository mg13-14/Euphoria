//
//  TSInjectPluginViewController.m
//  TrollStoreE
//

#import "TSInjectPluginViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define TSSTR(x) @x

@interface TSInjectPluginViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *fileLabel;
@end

@implementation TSInjectPluginViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"注入插件";
	self.view.backgroundColor = [UIColor secondarySystemBackgroundColor];

	UILabel *iconLabel = [[UILabel alloc] init];
	iconLabel.text = @"🧩";
	iconLabel.font = [UIFont systemFontOfSize:64];
	iconLabel.textAlignment = NSTextAlignmentCenter;
	iconLabel.numberOfLines = 0;
	iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:iconLabel];

	_statusLabel = [[UILabel alloc] init];
	_statusLabel.text = @"导入安装包与插件，注入后用自带 ldid 重签";
	_statusLabel.font = [UIFont systemFontOfSize:13];
	_statusLabel.textColor = [UIColor secondaryLabelColor];
	_statusLabel.textAlignment = NSTextAlignmentCenter;
	_statusLabel.numberOfLines = 0;
	_statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_statusLabel];

	UIButton *importButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[importButton setTitle:TSSTR("导入安装包") forState:UIControlStateNormal];
	[importButton.titleLabel setFont:[UIFont boldSystemFontOfSize:17]];
	[importButton addTarget:self action:@selector(importTapped:) forControlEvents:UIControlEventTouchUpInside];
	importButton.translatesAutoresizingMaskIntoConstraints = NO;
	[importButton.layer setCornerRadius:12];
	importButton.backgroundColor = [UIColor tintColor];
	[self.view addSubview:importButton];

	UIButton *pluginButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[pluginButton setTitle:TSSTR("选择插件（.dylib / .framework）") forState:UIControlStateNormal];
	[pluginButton addTarget:self action:@selector(pluginTapped:) forControlEvents:UIControlEventTouchUpInside];
	pluginButton.translatesAutoresizingMaskIntoConstraints = NO;
	pluginButton.layer.cornerRadius = 12;
	[self.view addSubview:pluginButton];

	_fileLabel = [[UILabel alloc] init];
	_fileLabel.font = [UIFont fontWithName:@"Menlo" size:12];
	_fileLabel.textColor = [UIColor secondaryLabelColor];
	_fileLabel.numberOfLines = 0;
	_fileLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_fileLabel];

	[NSLayoutConstraint activateConstraints:@[
		[iconLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40],
		[iconLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_statusLabel.topAnchor constraintEqualToAnchor:iconLabel.bottomAnchor constant:8],
		[_statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
		[_statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
		[importButton.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:28],
		[importButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[importButton.widthAnchor constraintEqualToConstant:260],
		[importButton.heightAnchor constraintEqualToConstant:48],
		[pluginButton.topAnchor constraintEqualToAnchor:importButton.bottomAnchor constant:14],
		[pluginButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[pluginButton.widthAnchor constraintEqualToConstant:260],
		[pluginButton.heightAnchor constraintEqualToConstant:48],
		[_fileLabel.topAnchor constraintEqualToAnchor:pluginButton.bottomAnchor constant:22],
		[_fileLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
		[_fileLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
	]];
}

#pragma mark - 导入

- (void)importTapped:(id)sender
{
	UTType *ipaType = [UTType typeWithIdentifier:@"com.apple.itunes-ipa" error:nil];
	NSArray<UTType *> *types = ipaType ? @[ipaType, [UTType data]] : @[[UTType data]];
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
	picker.delegate = self;
	picker.allowsMultipleSelection = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
	NSURL *url = urls.firstObject;
	NSString *dest = [NSTemporaryDirectory() stringByAppendingPathComponent:url.lastPathComponent];
	[[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
	BOOL ok = [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:nil];
	NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:dest];
	NSData *magic = [fh readDataOfLength:2];
	[fh closeFile];
	const uint8_t *m = (const uint8_t *)magic.bytes;
	BOOL isZip = (magic.length == 2 && m[0] == 0x50 && m[1] == 0x4B);
	if (ok && isZip) {
		_importedIPAPath = dest;
		_fileLabel.text = [NSString stringWithFormat:@"✅ 已导入：%@（%lld KB）\n下一步：选择要注入的插件", url.lastPathComponent, (long long)([[NSFileManager defaultManager] attributesOfItemAtPath:dest error:nil].fileSize / 1024)];
	}
	else {
		_importedIPAPath = nil;
		_fileLabel.text = @"❌ 导入失败：文件不是有效的 .ipa/.tipa（ZIP 头校验未通过）";
	}
}

- (void)pluginTapped:(id)sender
{
	if (!_importedIPAPath) {
		_fileLabel.text = @"⚠️ 请先导入安装包，再选择插件";
		return;
	}
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[[UTType data]] inMode:UIDocumentPickerModeImport];
	picker.delegate = self;
	picker.allowsMultipleSelection = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

/*
 架构注记（引擎接线点，详见 docs/TrollStoreE_功能设计.md）：
	1) 解包：libarchive（工程已链接 archive 库）抽出 Payload/*.app
	2) 注入：Mach-O 补 LC_LOAD_DYLIB（ChOma API），dylib 落 .app/Frameworks/
	3) 重签：posix_spawn 自带 ldid（Resources/ldid-ios-kit/bin/ldid，
	   构建期 scripts/embed_ldid.sh 将其 LC_RPATH 改为 @executable_path/Frameworks）
	4) 输出：进入主列表安装流程（复用 TSInstallationController）
	导入/校验/UI 状态链已可用；引擎接线随构建环境落地。
 */

@end
