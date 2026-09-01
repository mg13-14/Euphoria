//
//  EUSettingsController.h
//  Euphoria
//
//  Created by tomt000 on 08/01/2024.
//

#import <UIKit/UIKit.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "EUPSListController.h"
#import "EUExploit.h"

NS_ASSUME_NONNULL_BEGIN

@interface EUSettingsController : EUPSListController <UIImagePickerControllerDelegate>
{
    NSArray <EUExploit *>*_availableKernelExploits;
    NSArray <EUExploit *>*_availablePACBypasses;
    NSArray <EUExploit *>*_availablePPLBypasses;
    NSString *_lastKnownTheme;

    PSSpecifier *_customBootlogoEnabledSpecifier;
    PSSpecifier *_customBootlogoSpecifier;
}

@end

NS_ASSUME_NONNULL_END
