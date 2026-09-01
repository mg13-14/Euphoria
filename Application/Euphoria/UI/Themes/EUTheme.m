//
//  EUTheme.m
//  Euphoria
//
//  Created by tomt000 on 14/02/2024.
//

#import "EUTheme.h"
#import "UIImage+Blur.h"

@interface EUTheme ()
@property (nonatomic, retain) NSString *imageName;
@end

@implementation EUTheme

- (id)initWithDictionary: (NSDictionary *)dictionary
{
    self = [super init];
    if (self) {
        self.name = [dictionary objectForKey:@"name"];
        self.icon = [dictionary objectForKey:@"icon"];
        self.key = [dictionary objectForKey:@"key"];
        self.imageName = [dictionary objectForKey:@"image"];
        self.windowColor = [self colorFromHexString:[dictionary objectForKey:@"windowColor"]];
        self.actionMenuColor = [self colorFromHexString:[dictionary objectForKey:@"actionMenuColor"]];
        self.blur = [[dictionary objectForKey:@"blur"] floatValue];
        self.titleShadow = [[dictionary objectForKey:@"titleShadow"] boolValue];
    }
    return self;
}

- (UIColor*)colorFromHexString:(NSString*)hexString
{
    unsigned int hexInt = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner scanHexInt:&hexInt];
    return [UIColor colorWithRed:((CGFloat)((hexInt & 0xFF0000) >> 16))/255.0 green:((CGFloat)((hexInt & 0xFF00) >> 8))/255.0 blue:((CGFloat)(hexInt & 0xFF))/255.0 alpha:((CGFloat)((hexInt & 0xFF000000) >> 24))/255.0];
}

- (UIImage *)image
{
    if (_image == nil)
        _image = [[UIImage imageNamed:self.imageName] imageWithBlur:self.blur];
    return _image;
}

- (UIImage *)generateBootLogo
{
    // R35（用户 10:17-10:18 定案，"中间放个小图标，四周那些黑留给谁看"
    // +"把上面的那个标志去掉"+"直接让它变成应用图标，那个颜色就行了"）：
    // 旧实现=主题背景图(3000×2000 横图)+固定 350×350 EuphoriaLogo——横图在竖屏
    // 开机阶段等比缩放后四周黑边，且 350pt 小标志占比过小。
    // 新实现：竖屏全屏画布（1179×2556），背景=主应用图标背景板同款渐变
    // （#5A2B8D→#EB4F9D，主 AppIcon 中心列实测），中央=应用图标本体
    // （EUBootIcon，非 EuphoriaLogo 标志）放大至画布宽 50%；黑边来源根除。
    CGSize canvasSize = CGSizeMake(1179, 2556);
    UIImage *appIconImage = [UIImage imageNamed:@"EUBootIcon"];

    UIGraphicsBeginImageContextWithOptions(canvasSize, YES, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    // 应用图标背景板渐变（上 #5A2B8D → 下 #EB4F9D）
    CGFloat *components = (CGFloat []) {0x5A/255.0, 0x2B/255.0, 0x8D/255.0, 1.0,
                                         0xEB/255.0, 0x4F/255.0, 0x9D/255.0, 1.0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
    CGContextDrawLinearGradient(ctx, gradient, CGPointZero, CGPointMake(0, canvasSize.height), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    // 应用图标本体居中（宽 50%，等比；无资源时纯渐变全屏，不留黑不留标志）
    if (appIconImage) {
        CGFloat iconWidth = canvasSize.width * 0.5;
        CGFloat iconHeight = iconWidth * appIconImage.size.height / appIconImage.size.width;
        CGFloat ox = (canvasSize.width - iconWidth) / 2.0;
        CGFloat oy = (canvasSize.height - iconHeight) / 2.0;
        [appIconImage drawInRect:CGRectMake(ox, oy, iconWidth, iconHeight)];
    }

    UIImage *finalImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return finalImage;
}

@end
