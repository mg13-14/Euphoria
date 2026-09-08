//
//  EUStandaloneLogger.m
//  TrollE-Installer
//
//  抽离：并行搜索员C，2026-09-03（解耦点 #1，替代 EUUIManager.sendLog）
//

#import "EUStandaloneLogger.h"

static EUStandaloneLogger *_shared = nil;
static dispatch_queue_t _logQueue = NULL;

@implementation EUStandaloneLogger

+ (instancetype)sharedLogger
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[self alloc] init];
        _logQueue = dispatch_queue_create("dev.euphoria.trolle-installer.log", DISPATCH_QUEUE_SERIAL);
    });
    return _shared;
}

- (void)emit:(NSString *)line
{
    NSLog(@"[TrollE-Installer] %@", line);
    void (^cb)(NSString *) = self.onLog;
    if (cb) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cb(line);
        });
    }
}

- (void)log:(NSString *)fmt, ...
{
    va_list args;
    va_start(args, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    dispatch_async(_logQueue, ^{ [self emit:line]; });
}

- (void)logDebug:(NSString *)fmt, ...
{
    va_list args;
    va_start(args, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    dispatch_async(_logQueue, ^{ [self emit:line]; });
}

@end
