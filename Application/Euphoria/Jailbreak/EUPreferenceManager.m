//
//  PreferenceManager.m
//  Euphoria
//
//  Created by Lars Fröder on 13.01.24.
//

#import "EUPreferenceManager.h"

@implementation EUPreferenceManager

+ (instancetype)sharedManager
{
    static EUPreferenceManager *preferenceManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        preferenceManager = [[EUPreferenceManager alloc] init];
    });
    return preferenceManager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSString *home = [NSString stringWithUTF8String:getenv("HOME")];
        _preferencesPath = [home stringByAppendingPathComponent:@"Library/Preferences/dev.euphoria.Euphoria.plist"];
        [self loadPreferences];
    }
    return self;
}

- (void)loadPreferences
{
    _preferences = [NSDictionary dictionaryWithContentsOfFile:_preferencesPath].mutableCopy ?: [NSMutableDictionary new];
}

- (void)savePreferences
{
    [_preferences writeToFile:_preferencesPath atomically:YES];
}

- (id)preferenceValueForKey:(NSString *)key
{
    return [_preferences objectForKey:key];
}

- (BOOL)boolPreferenceValueForKey:(NSString *)key fallback:(BOOL)fallback
{
    NSNumber *num = [self preferenceValueForKey:key];
    if (num) {
        return num.boolValue;
    }
    return fallback;
}

- (void)setPreferenceValue:(NSObject *)obj forKey:(NSString *)key
{
    [_preferences setObject:obj forKey:key];
    [self savePreferences];
}

- (void)removePreferenceValueForKey:(NSString *)key
{
    [_preferences removeObjectForKey:key];
    [self savePreferences];
}

@end
