//
//  TSIpaEditorViewController.m
//  TrollStoreE
//

#import "TSIpaEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TSIpaEditorViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UILabel *fileLabel;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *bundleIdField;
@property (nonatomic, strong) UITextField *versionField;
@end

@implementation TSIpaEditorViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"修改安装包";
	self.view.backgroundColor = [UIColor secondarySystemBackgroundColor];

	UILabel *iconLabel = [[UILabel alloc] init];
	iconLabel.text = @"✏️";
	iconLabel.font = [UIFont systemFontOfSize:64];
	iconLabel.textAlignment = NSTextAlignmentCenter;
	iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:iconLabel];

	_fileLabel = [[UILabel alloc] init];
	_fileLabel.text = @"导入 .ipa/.tipa 后可读取并修改包信息";
	_fileLabel.font = [UIFont fontWithName:@"Menlo" size:12];
	_fileLabel.textColor = [UIColor secondaryLabelColor];
	_fileLabel.numberOfLines = 0;
	_fileLabel.textAlignment = NSTextAlignmentCenter;
	_fileLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_fileLabel];

	UIButton *importButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[importButton setTitle:@"导入安装包（.ipa / .tipa）" forState:UIControlStateNormal];
	[importButton.titleLabel setFont:[UIFont boldSystemFontOfSize:17]];
	[importButton addTarget:self action:@selector(importTapped:) forControlEvents:UIControlEventTouchUpInside];
	importButton.translatesAutoresizingMaskIntoConstraints = NO;
	importButton.layer.cornerRadius = 12;
	importButton.backgroundColor = [UIColor tintColor];
	[self.view addSubview:importButton];

	UILabel *nameTitle = [[UILabel alloc] init];
	nameTitle.text = @"应用名称";
	nameTitle.font = [UIFont systemFontOfSize:13];
	nameTitle.textColor = [UIColor secondaryLabelColor];
	nameTitle.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:nameTitle];
	_nameField = [[UITextField alloc] init];
	_nameField.placeholder = @"读取后回填，可修改";
	_nameField.borderStyle = UITextBorderStyleRoundedRect;
	_nameField.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_nameField];

	UILabel *bundleIdTitle = [[UILabel alloc] init];
	bundleIdTitle.text = @"包名 (Bundle ID)";
	bundleIdTitle.font = [UIFont systemFontOfSize:13];
	bundleIdTitle.textColor = [UIColor secondaryLabelColor];
	bundleIdTitle.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:bundleIdTitle];
	_bundleIdField = [[UITextField alloc] init];
	_bundleIdField.placeholder = @"读取后回填，可修改";
	_bundleIdField.borderStyle = UITextBorderStyleRoundedRect;
	_bundleIdField.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_bundleIdField];

	UILabel *versionTitle = [[UILabel alloc] init];
	versionTitle.text = @"版本号";
	versionTitle.font = [UIFont systemFontOfSize:13];
	versionTitle.textColor = [UIColor secondaryLabelColor];
	versionTitle.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:versionTitle];
	_versionField = [[UITextField alloc] init];
	_versionField.placeholder = @"读取后回填，可修改";
	_versionField.borderStyle = UITextBorderStyleRoundedRect;
	_versionField.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_versionField];

	UIButton *exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[exportButton setTitle:@"导出修改后的安装包" forState:UIControlStateNormal];
	[exportButton addTarget:self action:@selector(exportTapped:) forControlEvents:UIControlEventTouchUpInside];
	exportButton.translatesAutoresizingMaskIntoConstraints = NO;
	exportButton.layer.cornerRadius = 12;
	[self.view addSubview:exportButton];

	[NSLayoutConstraint activateConstraints:@[
		[iconLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:30],
		[iconLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_fileLabel.topAnchor constraintEqualToAnchor:iconLabel.bottomAnchor constant:6],
		[_fileLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_fileLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
		[_fileLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
		[importButton.topAnchor constraintEqualToAnchor:_fileLabel.bottomAnchor constant:20],
		[importButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[importButton.widthAnchor constraintEqualToConstant:260],
		[importButton.heightAnchor constraintEqualToConstant:44],
		[nameTitle.topAnchor constraintEqualToAnchor:importButton.bottomAnchor constant:20],
		[nameTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
		[nameField.topAnchor constraintEqualToAnchor:nameTitle.bottomAnchor constant:6],
		[nameField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
		[nameField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
		[bundleIdTitle.topAnchor constraintEqualToAnchor:nameField.bottomAnchor constant:14],
		[bundleIdTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
		[bundleIdField.topAnchor constraintEqualToAnchor:bundleIdTitle.bottomAnchor constant:6],
		[bundleIdField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
		[bundleIdField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
		[versionTitle.topAnchor constraintEqualToAnchor:bundleIdField.bottomAnchor constant:14],
		[versionTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
		[versionField.topAnchor constraintEqualToAnchor:versionTitle.bottomAnchor constant:6],
		[versionField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
		[versionField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
		[exportButton.topAnchor constraintEqualToAnchor:versionField.bottomAnchor constant:22],
		[exportButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[exportButton.widthAnchor constraintEqualToConstant:260],
		[exportButton.heightAnchor constraintEqualToConstant:44],
	]];
}

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
		_fileLabel.text = [NSString stringWithFormat:@"✅ 已导入：%@（信息读取引擎接线后自动回填）", url.lastPathComponent];
	}
	else {
		_fileLabel.text = @"❌ 导入失败：不是有效的 .ipa/.tipa";
	}
}

- (void)exportTapped:(id)sender
{
	if ([_fileLabel.text hasPrefix:@"✅"]) {
		_fileLabel.text = [NSString stringWithFormat:@"🚧 重打包引擎接线中：解包(libarchive) → 改 Info.plist(名称=%@ 包名=%@ 版本=%@) → 自带 ldid 重签 → 导出", _nameField.text ?: @"-", _bundleIdField.text ?: @"-", _versionField.text ?: @"-"];
	}
	else {
		_fileLabel.text = @"⚠️ 请先导入安装包";
	}
}

@end
