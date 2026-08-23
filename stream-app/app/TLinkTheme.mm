#import "TLinkTheme.h"

static NSString *const kTLinkAppearanceDefaultsKey = @"TLinkAppearanceStyle";

@implementation TLinkTheme

#pragma mark - Colors

+ (UIColor *)accentColor { return [UIColor systemBlueColor]; }
+ (UIColor *)statusRunningColor { return [UIColor systemGreenColor]; }
+ (UIColor *)statusDegradedColor { return [UIColor systemOrangeColor]; }
+ (UIColor *)statusStoppedColor { return [UIColor systemRedColor]; }

+ (UIColor *)cardBackgroundColor
{
    return [UIColor secondarySystemGroupedBackgroundColor];
}

+ (UIColor *)subtleTextColor { return [UIColor secondaryLabelColor]; }

#pragma mark - Typography

+ (UIFont *)titleFont { return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2]; }
+ (UIFont *)headlineFont { return [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; }
+ (UIFont *)bodyFont { return [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; }
+ (UIFont *)captionFont { return [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; }

+ (UIFont *)logFont
{
    UIFont *menlo = [UIFont fontWithName:@"Menlo" size:11.0];
    if (menlo) return menlo;
    return [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
}

#pragma mark - Metrics

+ (CGFloat)cardCornerRadius { return 18.0; }
+ (CGFloat)controlCornerRadius { return 10.0; }
+ (CGFloat)cardPadding { return 16.0; }

#pragma mark - Appearance mode

+ (TLinkAppearanceStyle)currentAppearanceStyle
{
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:kTLinkAppearanceDefaultsKey];
    if (!value) return TLinkAppearanceStyleLight; // keep the legacy light look by default
    NSInteger style = value.integerValue;
    if (style < TLinkAppearanceStyleSystem || style > TLinkAppearanceStyleDark) {
        return TLinkAppearanceStyleLight;
    }
    return (TLinkAppearanceStyle)style;
}

+ (void)setCurrentAppearanceStyle:(TLinkAppearanceStyle)style
{
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)style forKey:kTLinkAppearanceDefaultsKey];
}

+ (NSString *)displayNameForAppearanceStyle:(TLinkAppearanceStyle)style
{
    switch (style) {
        case TLinkAppearanceStyleSystem: return @"System";
        case TLinkAppearanceStyleDark: return @"Dark";
        case TLinkAppearanceStyleLight:
        default: return @"Light";
    }
}

+ (void)applyCurrentAppearanceStyleToWindow:(UIWindow *)window
{
    if (!window) return;
    switch ([self currentAppearanceStyle]) {
        case TLinkAppearanceStyleSystem:
            window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
            break;
        case TLinkAppearanceStyleDark:
            window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            break;
        case TLinkAppearanceStyleLight:
        default:
            window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            break;
    }
}

#pragma mark - Factories

+ (UIButton *)buttonWithTitle:(NSString *)title
                       symbol:(NSString *)symbolName
                        style:(TLinkButtonStyle)style
                       target:(id)target
                       action:(SEL)action
{
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = nil;
        switch (style) {
            case TLinkButtonStylePrimary:
                configuration = [UIButtonConfiguration filledButtonConfiguration];
                configuration.baseBackgroundColor = [self accentColor];
                configuration.baseForegroundColor = [UIColor whiteColor];
                break;
            case TLinkButtonStyleDestructive:
                configuration = [UIButtonConfiguration tintedButtonConfiguration];
                configuration.baseForegroundColor = [self statusStoppedColor];
                break;
            case TLinkButtonStyleTinted:
                configuration = [UIButtonConfiguration tintedButtonConfiguration];
                configuration.baseForegroundColor = [self accentColor];
                break;
            case TLinkButtonStyleSecondary:
            default:
                configuration = [UIButtonConfiguration grayButtonConfiguration];
                break;
        }
        configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        configuration.title = title;
        if (symbolName.length > 0) {
            configuration.image = [UIImage systemImageNamed:symbolName];
            configuration.imagePadding = 6.0;
        }
        UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
        if (target && action) {
            [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        }
        return button;
    }

    // iOS 14 fallback: classic rounded-rect styling.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [self headlineFont];
    button.layer.cornerRadius = [self controlCornerRadius];
    button.clipsToBounds = YES;
    switch (style) {
        case TLinkButtonStylePrimary:
            button.backgroundColor = [self accentColor];
            [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            break;
        case TLinkButtonStyleDestructive:
            button.backgroundColor = [[self statusStoppedColor] colorWithAlphaComponent:0.12];
            [button setTitleColor:[self statusStoppedColor] forState:UIControlStateNormal];
            break;
        case TLinkButtonStyleTinted:
            button.backgroundColor = [[self accentColor] colorWithAlphaComponent:0.12];
            [button setTitleColor:[self accentColor] forState:UIControlStateNormal];
            break;
        case TLinkButtonStyleSecondary:
        default:
            button.backgroundColor = [UIColor secondarySystemFillColor];
            break;
    }
    if (target && action) {
        [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

+ (UIView *)cardContainerView
{
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [self cardBackgroundColor];
    card.layer.cornerRadius = [self cardCornerRadius];
    card.layer.masksToBounds = NO;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.06;
    card.layer.shadowRadius = 8.0;
    card.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    return card;
}

+ (UIView *)statusDotViewWithDiameter:(CGFloat)diameter
{
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, diameter, diameter)];
    dot.layer.cornerRadius = diameter / 2.0;
    dot.layer.masksToBounds = YES;
    return dot;
}

+ (UIStackView *)verticalStackWithSpacing:(CGFloat)spacing
{
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

@end
