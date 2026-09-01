//
//  EUThemeManager.m
//  Euphoria
//
//  Created by tomt000 on 14/02/2024.
//

#import "EUThemeManager.h"
#import "EUPreferenceManager.h"

@implementation EUThemeManager

+ (instancetype)sharedInstance
{
    static EUThemeManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[EUThemeManager alloc] init];
    });
    return sharedManager;
}

- (id)init
{
    self = [super init];
    if (self) {
        self.themes = [[NSMutableArray alloc] init];
        
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Themes" ofType:@"plist"];
        NSArray *themes = [NSArray arrayWithContentsOfFile:path];

        for (NSDictionary *theme in themes) {
            EUTheme *newTheme = [[EUTheme alloc] initWithDictionary:theme];
            [((NSMutableArray *)self.themes) addObject:newTheme];
        }

    }
    return self;
}

- (NSArray*)getAvailableThemeKeys
{
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    for (EUTheme *theme in _themes) {
        [keys addObject:theme.key];
    }
    return keys;
}

- (NSArray*)getAvailableThemeNames
{
    NSMutableArray *names = [[NSMutableArray alloc] init];
    for (EUTheme *theme in _themes) {
        [names addObject:theme.name];
    }
    return names;
}

- (EUTheme*)getThemeForKey:(NSString*)key
{
    for (EUTheme *theme in _themes) {
        if ([theme.key isEqualToString:key]) {
            return theme;
        }
    }
    return nil;
}

- (EUTheme*)enabledTheme
{
    id value = [[EUPreferenceManager sharedManager] preferenceValueForKey:@"theme"];
    if (!value)
        return self.themes.firstObject;
    return [self getThemeForKey:value] ?: self.themes.firstObject;
}


+ (UIColor*)menuColorWithAlpha:(float)alpha
{
    EUTheme *theme = [[EUThemeManager sharedInstance] enabledTheme];
    
    UIColor *color = theme.actionMenuColor;
    CGFloat red, green, blue, currentAlpha;
    [color getRed:&red green:&green blue:&blue alpha:&currentAlpha];
    return [UIColor colorWithRed:red green:green blue:blue alpha:currentAlpha * alpha];
}


@end
