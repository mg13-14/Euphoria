//
//  EUActionButton.h
//  Euphoria
//
//  Created by tomt000 on 07/01/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface EUActionMenuButton : UIButton

@property (nonatomic) BOOL bottomSeparator;

+(EUActionMenuButton*)buttonWithAction:(UIAction *)action chevron:(BOOL)chevron;

@end

NS_ASSUME_NONNULL_END
