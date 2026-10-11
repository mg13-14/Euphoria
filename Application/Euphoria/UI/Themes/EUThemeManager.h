//
//  EUThemeManager.h
//  Euphoria
//
//  Created by tomt000 on 14/02/2024.
//

#import <Foundation/Foundation.h>
#import "EUTheme.h"

NS_ASSUME_NONNULL_BEGIN

@interface EUThemeManager : NSObject

@property (nonatomic, retain) NSArray<EUTheme*> *themes;

+ (instancetype)sharedInstance;

+ (UIColor*)menuColorWithAlpha:(float)alpha;
- (NSArray*)getAvailableThemeKeys;
- (NSArray*)getAvailableThemeNames;
- (EUTheme*)getThemeForKey:(NSString*)key;
- (EUTheme*)enabledTheme;

@end

NS_ASSUME_NONNULL_END
