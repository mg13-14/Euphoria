//
//  EUPkgManagerPickerViewController.m
//  Euphoria
//
//  Created by tomt000 on 11/02/2024.
//

#import "EUPkgManagerPickerViewController.h"
#import "EUPkgManagerPickerView.h"
#import "EUEnvironmentManager.h"


@interface EUPkgManagerPickerViewController ()

@end

@implementation EUPkgManagerPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    EUPkgManagerPickerView *picker = [[EUPkgManagerPickerView alloc] initWithCallback:^(BOOL success) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[EUEnvironmentManager sharedManager] reinstallPackageManagers];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.navigationController popViewControllerAnimated:YES];
            });
        });
    }];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:picker];
    [NSLayoutConstraint activateConstraints:@[
        [picker.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [picker.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [picker.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [picker.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}


@end
