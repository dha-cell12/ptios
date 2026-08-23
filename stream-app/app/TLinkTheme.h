#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// TLinkTheme
//
// Central design tokens for the StreamControl UI: colors, fonts, metrics and
// small view factories. Screens should read tokens from here instead of
// hardcoding colors/fonts so the whole app can be restyled in one place.
//
// Deployment target is iOS 14.0; iOS 15-only APIs (UIButtonConfiguration) are
// used behind availability checks with classic fallbacks.
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, TLinkButtonStyle) {
    TLinkButtonStylePrimary,      // filled accent (main action)
    TLinkButtonStyleSecondary,    // gray fill (neutral action)
    TLinkButtonStyleTinted,       // tinted accent (secondary emphasis)
    TLinkButtonStyleDestructive,  // tinted red (stop/delete style actions)
};

typedef NS_ENUM(NSInteger, TLinkAppearanceStyle) {
    TLinkAppearanceStyleSystem = 0,
    TLinkAppearanceStyleLight = 1,
    TLinkAppearanceStyleDark = 2,
};

@interface TLinkTheme : NSObject

// Colors
@property (class, nonatomic, readonly) UIColor *accentColor;
@property (class, nonatomic, readonly) UIColor *statusRunningColor;
@property (class, nonatomic, readonly) UIColor *statusDegradedColor;
@property (class, nonatomic, readonly) UIColor *statusStoppedColor;
@property (class, nonatomic, readonly) UIColor *cardBackgroundColor;
@property (class, nonatomic, readonly) UIColor *subtleTextColor;

// Typography (Dynamic Type aware)
@property (class, nonatomic, readonly) UIFont *titleFont;
@property (class, nonatomic, readonly) UIFont *headlineFont;
@property (class, nonatomic, readonly) UIFont *bodyFont;
@property (class, nonatomic, readonly) UIFont *captionFont;
@property (class, nonatomic, readonly) UIFont *logFont;

// Metrics
@property (class, nonatomic, readonly) CGFloat cardCornerRadius;
@property (class, nonatomic, readonly) CGFloat controlCornerRadius;
@property (class, nonatomic, readonly) CGFloat cardPadding;

// Appearance mode (persisted in NSUserDefaults)
+ (TLinkAppearanceStyle)currentAppearanceStyle;
+ (void)setCurrentAppearanceStyle:(TLinkAppearanceStyle)style;
+ (NSString *)displayNameForAppearanceStyle:(TLinkAppearanceStyle)style;
+ (void)applyCurrentAppearanceStyleToWindow:(nullable UIWindow *)window;

// Factories
+ (UIButton *)buttonWithTitle:(NSString *)title
                       symbol:(nullable NSString *)symbolName
                        style:(TLinkButtonStyle)style
                       target:(nullable id)target
                       action:(nullable SEL)action;
+ (UIView *)cardContainerView;
+ (UIView *)statusDotViewWithDiameter:(CGFloat)diameter;
+ (UIStackView *)verticalStackWithSpacing:(CGFloat)spacing;

@end

NS_ASSUME_NONNULL_END
