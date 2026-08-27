//
//  EULyricsLogView.h
//  Euphoria
//
//  Created by tomt000 on 13/01/2024.
//

#import <UIKit/UIKit.h>
#import "EULogViewProtocol.h"
#import "EULoadingIndicator.h"
#import "EULyricsLogItemView.h"

NS_ASSUME_NONNULL_BEGIN

/// They're just called lyrics log view because they remind me of apple music lyrics 🤫
@interface EULyricsLogView : UIView<EULogViewProtocol>
{
    UIImage *_checkmarkImage;
    UIImage *_exclamationMarkImage;
    UIImage *_unlockedImage;
}

@property (nonatomic, strong) UIStackView *stackView;

@end

NS_ASSUME_NONNULL_END
