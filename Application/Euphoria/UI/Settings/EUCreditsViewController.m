//
//  EUCreditsViewController.m
//  Euphoria
//
//  Created by tomt000 on 08/01/2024.
//

#import "EUCreditsViewController.h"
#import "EULicenseViewController.h"
#import "EUUIManager.h"
#import "EUEnvironmentManager.h"
#import <Preferences/PSSpecifier.h>

@interface EUCreditsViewController ()

@end

@implementation EUCreditsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (id)specifiers
{
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Credits" target:self];

        PSSpecifier *headerSpecifier = _specifiers[0];
        [headerSpecifier setProperty:[NSString stringWithFormat:@"Euphoria %@ - %@", [EUEnvironmentManager sharedManager].appVersionDisplayString, EULocalizedString(@"Menu_Credits_Title")] forKey:@"title"];
    }
    return _specifiers;
}

- (void)openSourceCode
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/euphoria-jb/Euphoria"] options:@{} completionHandler:nil];
}

- (void)openDiscord
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://discord.gg/jb"] options:@{} completionHandler:nil];
}

- (void)openLicense
{
    [self.navigationController pushViewController:[[EULicenseViewController alloc] init] animated:YES];
}

@end
