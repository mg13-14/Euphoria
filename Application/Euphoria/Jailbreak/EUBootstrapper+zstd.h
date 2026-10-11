//
//  Bootstrapper.h
//  Euphoria
//
//  Created by Lars Fröder on 09.01.24.
//

#import <Foundation/Foundation.h>

#import "EUBootstrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface EUBootstrapper (zstd)

- (NSError *)decompressZstd:(NSString *)zstdPath toTar:(NSString *)tarPath;

@end

NS_ASSUME_NONNULL_END
