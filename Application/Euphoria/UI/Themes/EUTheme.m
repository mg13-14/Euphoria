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
    // The boot logo is the app icon, centered on a black background
    UIImage *appIcon = [UIImage imageNamed:@"AppIconImage"];
    UIImage *overlayImage = appIcon ?: [UIImage imageNamed:@"EuphoriaLogo"];

    CGSize canvasSize = CGSizeMake(2000, 2000);
    CGSize overlaySize = CGSizeMake(380, 380);
    CGPoint overlayOrigin = CGPointMake((canvasSize.width - overlaySize.width) / 2.0,
                                        (canvasSize.height - overlaySize.height) / 2.0);

    UIGraphicsBeginImageContextWithOptions(canvasSize, YES, 1.0);

    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, canvasSize.width, canvasSize.height));

    if (appIcon) {
        // Clip to a rounded rect so the icon looks like it does on the home screen
        UIBezierPath *clipPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(overlayOrigin.x, overlayOrigin.y, overlaySize.width, overlaySize.height)
                                                             cornerRadius:overlaySize.width * 0.2237];
        [clipPath addClip];
    }

    [overlayImage drawInRect:CGRectMake(overlayOrigin.x, overlayOrigin.y, overlaySize.width, overlaySize.height)];

    UIImage *finalImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return finalImage;
}

@end
