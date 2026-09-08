//
//  EUFairyStyle.h
//  TrollE-Installer
//
//  仙境风 UI 工具集（docs/08-仙境风UI设计规范.md §1–§4 落地）：
//   深空三段渐变 / 星尘粒子 / 极光按钮+流光 / 毛玻璃卡片 / 状态徽标点 / 成功涟漪。
//  全 CA 层原生实现，零第三方依赖；ReduceMotion 自动降级（§4 无障碍）。
//  色值/圆角/描边逐项按 08 规范 §2/§3（验收：色差 ≤5%）。
//  B 线 2026-09-05（用户 00:11/00:32 定案"仙境"口径）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface EUFairyStyle : NSObject

/// 深空底色（§2：#0B0E2A→#1B1443→#2E1B5E 三段纵向渐变）。
/// 插入 view.layer 最底层，随视图 bounds 变化需调用方在 viewDidLayoutSubviews 里同步 frame。
+ (CAGradientLayer *)deepSpaceBackgroundInView:(UIView *)view;

/// 星尘粒子层（§4-1：birthRate 12/s、上升漂移、1.5pt 月白 60% 圆点）。
/// ReduceMotion 开启时返回 nil（调用方跳过挂载）；仅挂主背景层，卡片层不加（§3 克制律）。
+ (nullable CAEmitterLayer *)stardustLayerInView:(UIView *)view;

/// 极光渐变按钮样式（§2/§3-2：横向三段 #7CF3D0→#5E8BFF→#B47CFF、44pt 高、16pt 圆角、
/// 按压 scale 0.97、locations 3s 循环流光）。installing=YES 时流光保留+紫光脉冲
/// （§6-2"停粒子保流光"——按钮层从不停粒子，恒无粒子，脉冲=opacity 呼吸）。
+ (void)styleAuroraButton:(UIButton *)button installing:(BOOL)installing;

/// 次级按钮（选择文件等）：深空半透玻璃面 + 月白文字 + 16pt 圆角（主按钮的克制版）。
+ (void)styleSecondaryButton:(UIButton *)button installing:(BOOL)installing;

/// 毛玻璃卡片（§3-1：systemChromeMaterialDark + 24pt 圆角 + 1px 月白 12% 描边 +
/// 浮起阴影 #000 40%、y=12、blur=32）。返回带卡片的容器，contentView 由调用方布局。
+ (UIView *)glassCard;

/// 卡片描边布局辅助（调用方在卡片布局完成后调用；返回描边层供同步 frame）。
+ (CAShapeLayer *)attachBorderToView:(UIView *)view;

/// 状态徽标点（§3-3：8pt 圆点 + 呼吸光晕 shadowRadius 4→10 循环 2.4s）。
/// 颜色由调用方按 §5 四态传入（成功青绿/警示琥珀/危险玫红/极光蓝紫）。
+ (UIView *)statusDotWithColor:(UIColor *)color;

/// 成功涟漪（§4-3：12% 月白圆环从源视图中心扩散，1.2s 淡出后自移除）。
+ (void)rippleFromView:(UIView *)sourceView;

/// 色板（§2）——主 App 与独立 VC 共用同值，防两入口漂移。
+ (UIColor *)colorSuccess;   // 荧光青绿 #5CE8B5
+ (UIColor *)colorWarning;   // 暖琥珀 #FFB86B
+ (UIColor *)colorDanger;    // 玫红 #FF6B9D
+ (UIColor *)colorAurora;    // 极光蓝紫（引擎A 徽标）
+ (UIColor *)colorPulse;     // 紫光脉冲 #B47CFF（安装中徽标，§5）
+ (UIColor *)colorMoonWhite; // 月白主文 #EAEAF2
+ (UIColor *)colorMoonWhiteDim; // 月白辅文 60%

/// 字体：SF Mono 优先、Menlo 兜底（iOS 无 SF Mono 家用字体时的等宽降级，如实）。
+ (UIFont *)monospaceFontOfSize:(CGFloat)size;

@end

NS_ASSUME_NONNULL_END
