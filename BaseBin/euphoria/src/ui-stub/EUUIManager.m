#import "EUUIManager.h"

@implementation EUUIManager

+ (instancetype)sharedInstance
{
    static EUUIManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[EUUIManager alloc] init];
    });
    return sharedInstance;
}

- (void)sendLog:(NSString*)log debug:(BOOL)debug update:(BOOL)update
{
	if (!debug) {
		printf("%s\n", log.UTF8String);
	}
	else {
		printf("[d] %s\n", log.UTF8String);
	}
}

- (void)sendLog:(NSString*)log debug:(BOOL)debug
{
	[self sendLog:log debug:debug update:NO];
}

- (NSArray *)enabledPackageManagers
{
	return nil;
}

- (id)renderBootLogo
{
    return nil;
}

@end


NSString *EULocalizedString(NSString *string)
{
	return string;
}