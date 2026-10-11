//
//  main.m
//  Euphoria
//
//  Created by Lars Fröder on 23.09.23.
//

#import <UIKit/UIKit.h>
#import "EUAppDelegate.h"

#import "EUEnvironmentManager.h"
#import <libjailbreak/info.h>
#import <libjailbreak/jbclient_xpc.h>

int main(int argc, char * argv[]) {
    if (argc >= 3) {
        if (!strcmp(argv[1], "trollstore")) {
            if (!strcmp(argv[2], "delete-bootstrap")) {
                [[EUEnvironmentManager sharedManager] deleteBootstrap];
            }
            else if (!strcmp(argv[2], "hide-jailbreak")) {
                [[EUEnvironmentManager sharedManager] setJailbreakHidden:YES];
            }
            return 0;
        }
    }
    
    if (argc >= 2) {
        // Legacy, called by Euphoria 1.x before initiating a jbupdate
        // As updating from 1.x to 2.x is unsupported, just initiate a device reboot
        if (!strcmp(argv[1], "prepare_jbupdate")) {
            [[EUEnvironmentManager sharedManager] reboot];
            return 0;
        }
    }
    
    if ([EUEnvironmentManager sharedManager].isJailbroken) {
        setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin:/var/jb/sbin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/usr/bin", 1);
        setenv("TERM", "xterm-256color", 1);
    }
    
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([EUAppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
