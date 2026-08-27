//
//  EULyricsLogItemView.h
//  Euphoria
//
//  Created by tomt000 on 18/01/2024.
//

#import <UIKit/UIKit.h>
#import "EULoadingIndicator.h"

NS_ASSUME_NONNULL_BEGIN

@interface EULyricsLogItemView : UIView

@property (nonatomic) UILabel *label;
@property (nonatomic) EULoadingIndicator *loadingIndicator;
@property (nonatomic) BOOL completed;
@property (nonatomic) UIImpactFeedbackGenerator *feedbackGenerator;

@property (nonatomic) UIImage *completedImage;
@property (nonatomic) UIImage *failedImage;
@property (nonatomic) UIImage *successImage;

- (id)initWithString:(NSString *)string completedImage:(UIImage *)completedImage failedImage:(UIImage *)failedImage successImage:(UIImage *)successImage;
- (void)setCompleted;
- (void)setFailed;
- (void)setSuccess;

@end

NS_ASSUME_NONNULL_END
