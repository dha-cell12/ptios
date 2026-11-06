@implementation TouchIndicatorWindow {
    UIWindow *_window;
    TouchIndicatorView *touchIndicatorViewList[kTLinkTouchMaxFingerCount];
    TouchIndicatorCoordinateView *coordinateView[kTLinkTouchMaxFingerCount];
    UIColor *indicatorColor;
    UIFont *_coordinateFont;
    BOOL _visible;
}

- (id)init
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    self = [super init];
    if (self) {
        _window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenBoundsWidth, screenBoundsHeight)];
        if (!_window) return nil;
        _window.windowLevel = UIWindowLevelAlert;
        _window.backgroundColor = [UIColor clearColor];
        _window.userInteractionEnabled = NO;
        _window.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _window.hidden = YES;
        indicatorColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.7];
        _coordinateFont = [UIFont fontWithName:@"Trebuchet MS" size:11.0] ?: [UIFont systemFontOfSize:11.0];
    }
    return self;
}

- (void)hideIndicator:(int)index
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    if (!zx_indicatorValidFingerIndex(index)) return;
    [touchIndicatorViewList[index] removeFromSuperview];
    touchIndicatorViewList[index] = nil;
    [coordinateView[index] removeFromSuperview];
    coordinateView[index] = nil;
}

- (void)showIndicator:(int)index withX:(CGFloat)x andY:(CGFloat)y majorRadius:(CGFloat)radius
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    if (!zx_indicatorValidFingerIndex(index) || !_visible) return;
    [self hideIndicator:index];
    CGFloat size = radius * SIZE_INDIACTOR_TOUCH_RADIUS_RATIO;
    CGFloat half = size / 2;
    TouchIndicatorView *indicator = [[TouchIndicatorView alloc] initWithFrame:CGRectMake(x - half, y - half, size, size)];
    indicator.layer.cornerRadius = half;
    indicator.backgroundColor = indicatorColor;
    NSString *text = [NSString stringWithFormat:@"(%d, %d)", (int)(x * scale), (int)(y * scale)];
    CGFloat width = [text sizeWithAttributes:@{NSFontAttributeName:_coordinateFont}].width + 5;
    TouchIndicatorCoordinateView *coordinate = [[TouchIndicatorCoordinateView alloc] initWithFrame:CGRectMake(x + half + 5, y, width, COORDINATE_VIEW_HEIGHT)];
    coordinate.backgroundColor = indicatorColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, width, COORDINATE_VIEW_HEIGHT)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    label.font = _coordinateFont;
    [coordinate addSubview:label];
    coordinate.coordinateLabel = label;
    touchIndicatorViewList[index] = indicator;
    coordinateView[index] = coordinate;
    [_window addSubview:indicator];
    [_window addSubview:coordinate];
}

- (void)show
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    _visible = YES;
    _window.hidden = NO;
}

- (void)hide
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    _visible = NO;
    _window.hidden = YES;
    for (int i = 0; i < kTLinkTouchMaxFingerCount; i++) [self hideIndicator:i];
}

- (void)setIndicatorColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    indicatorColor = [UIColor colorWithRed:red/255 green:green/255 blue:blue/255 alpha:alpha];
    for (int i = 0; i < kTLinkTouchMaxFingerCount; i++) {
        touchIndicatorViewList[i].backgroundColor = indicatorColor;
        coordinateView[i].backgroundColor = indicatorColor;
    }
}

- (void)moveIndicator:(int)index x:(CGFloat)x y:(CGFloat)y majorRadius:(CGFloat)radius
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    if (!zx_indicatorValidFingerIndex(index) || !_visible || !touchIndicatorViewList[index]) return;
    CGFloat size = radius * SIZE_INDIACTOR_TOUCH_RADIUS_RATIO;
    CGFloat half = size / 2;
    touchIndicatorViewList[index].frame = CGRectMake(x - half, y - half, size, size);
    touchIndicatorViewList[index].layer.cornerRadius = half;
    NSString *text = [NSString stringWithFormat:@"(%d, %d)", (int)(x * scale), (int)(y * scale)];
    CGFloat width = [text sizeWithAttributes:@{NSFontAttributeName:_coordinateFont}].width + 5;
    coordinateView[index].coordinateLabel.text = text;
    coordinateView[index].coordinateLabel.frame = CGRectMake(0, 0, width, COORDINATE_VIEW_HEIGHT);
    coordinateView[index].frame = CGRectMake(x + half + 5, y, width, COORDINATE_VIEW_HEIGHT);
}

@end
