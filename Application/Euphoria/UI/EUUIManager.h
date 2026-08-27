//
//  EUUIManager.h
//  Euphoria
//
//  Created by tomt000 on 24/01/2024.
//

#import <Foundation/Foundation.h>
#import "EULogViewProtocol.h"
#import "EUDebugLogView.h"
#import "EUPreferenceManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface EUUIManager : NSObject
{
    EUPreferenceManager *_preferenceManager;
    NSDictionary *_fallbackLocalizations;
    NSLock *_logLock;
}

@property (nonatomic, readonly) NSString *bootlogoPath;
@property (nonatomic, retain) NSObject<EULogViewProtocol> *logView;
@property (atomic, retain) NSMutableArray<NSString*> *logRecord;

+ (instancetype)sharedInstance;

- (BOOL)isDebug;
- (void)sendLog:(NSString*)log debug:(BOOL)debug update:(BOOL)update;
- (void)sendLog:(NSString*)log debug:(BOOL)debug;
- (void)completeJailbreak;
- (void)startLogCapture;
- (void)shareLogRecordFromView:(UIView *)sourceView;
- (BOOL)isUpdateAvailable;
- (BOOL)environmentUpdateAvailable;
- (NSArray *)getLatestReleases;
- (NSString*)getLaunchedReleaseTag;
- (NSString*)getLatestReleaseTag;
- (NSArray *)getUpdatesInRange:(NSString *)start end:(NSString *)end;
- (bool)launchedReleaseNeedsManualUpdate;
- (NSArray*)availablePackageManagers;
- (NSArray*)enabledPackageManagerKeys;
- (NSArray*)enabledPackageManagers;
- (void)resetPackageManagers;
- (void)resetSettings;
- (void)setPackageManager:(NSString*)key enabled:(BOOL)enabled;
- (NSString *)localizedStringForKey:(NSString*)key;
- (UIImage *)renderBootLogo;

@end

NSString *EULocalizedString(NSString *string);

NS_ASSUME_NONNULL_END
