//
//  EUPSExploitListItemsControllerViewController.m
//  Euphoria
//
//  Created by Lars Fröder on 29.04.24.
//

#import "EUPSJetsamListItemsController.h"
#import "EUUIManager.h"

@interface EUPSJetsamListItemsController ()

@end

@implementation EUPSJetsamListItemsController

- (NSArray *)specifiers
{
    if (!_specifiers) {
        _specifiers = [super specifiers];
        PSSpecifier *jetsamDescriptionSpecifier = [PSSpecifier emptyGroupSpecifier];
        [jetsamDescriptionSpecifier setProperty:EULocalizedString(@"Jetsam_Description") forKey:@"footerText"];
        [(NSMutableArray *)_specifiers addObject:jetsamDescriptionSpecifier];
    }
    return _specifiers;
}

@end
