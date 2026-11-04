static id TLinkAXAttribute(TLinkAXElementRef element, uint32_t key, int *errorOut)
{
    if (TLinkNativeStopped()) return nil;
    if (!element || !sTLinkAXCopyAttribute) return nil;
    CFTypeRef value = NULL;
    int error = sTLinkAXCopyAttribute(element, (CFStringRef)(uintptr_t)key, &value);
    if (errorOut) *errorOut = error;
    if (error != 0) {
        if (value) CFRelease(value);
        return nil;
    }
    return value ? CFBridgingRelease(value) : nil;
}

static NSString *TLinkAXStringValue(id value)
{
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue] ?: @"";
    return @"";
}

static NSString *TLinkAXRoleForTraits(uint64_t traits)
{
    if (traits & UIAccessibilityTraitButton) return @"button";
    if (traits & UIAccessibilityTraitLink) return @"link";
    if (traits & UIAccessibilityTraitImage) return @"image";
    if (traits & UIAccessibilityTraitHeader) return @"heading";
    if (traits & UIAccessibilityTraitAdjustable) return @"adjustable";
    if (traits & UIAccessibilityTraitSearchField) return @"search_field";
    if (traits & UIAccessibilityTraitKeyboardKey) return @"keyboard_key";
    if (traits & UIAccessibilityTraitStaticText) return @"text";
    return @"element";
}

static NSDictionary *TLinkAXSerializeElement(TLinkAXElementRef element,
                                             CGRect screen,
                                             NSUInteger index)
{
    if (!element) return nil;
    @try {
        if (TLinkNativeStopped()) return nil;
        auto nativeBudget = TLinkCurrentNativeBudget();
        if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, nativeBudget ? (float)nativeBudget->remainingSeconds(0.10) : 0.10f);
        id frameValue = TLinkAXAttribute(element, 2003, NULL);
        CGRect frame = CGRectZero;
        if (!frameValue ||
            !sTLinkAXValueGetValue((__bridge CFTypeRef)frameValue, 3, &frame) ||
            !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
            !isfinite(frame.size.width) || !isfinite(frame.size.height)) {
            return nil;
        }

        id label = TLinkAXAttribute(element, 2001, NULL);
        id value = TLinkAXAttribute(element, 2006, NULL);
        id identifier = TLinkAXAttribute(element, 5019, NULL);
        id traitsValue = TLinkAXAttribute(element, 2004, NULL);
        uint64_t traits = [traitsValue respondsToSelector:@selector(unsignedLongLongValue)]
            ? (uint64_t)[traitsValue unsignedLongLongValue] : 0;
        BOOL enabled = (traits & UIAccessibilityTraitNotEnabled) == 0;
        BOOL hasSize = frame.size.width > 0.0 && frame.size.height > 0.0;
        BOOL interactiveTrait = (traits & (UIAccessibilityTraitButton |
                                           UIAccessibilityTraitLink |
                                           UIAccessibilityTraitAdjustable |
                                           UIAccessibilityTraitKeyboardKey)) != 0;
        BOOL clickable = enabled && hasSize &&
            (interactiveTrait || (traits & UIAccessibilityTraitStaticText) == 0);
        CGRect intersection = CGRectIntersection(frame, screen);
        BOOL intersectsScreen = !CGRectIsNull(intersection) && !CGRectIsEmpty(intersection);

        CGPoint point = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        id pointValue = TLinkAXAttribute(element, 2007, NULL);
        CGPoint candidate = point;
        if (pointValue &&
            sTLinkAXValueGetValue((__bridge CFTypeRef)pointValue, 1, &candidate) &&
            isfinite(candidate.x) && isfinite(candidate.y)) {
            point = candidate;
        }
        BOOL activationValid = CGRectContainsPoint(screen, point);
        if (!activationValid && CGRectContainsPoint(screen, CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)))) {
            point = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
            activationValid = YES;
        }

        return @{
            @"index": @(index),
            @"label": TLinkAXStringValue(label),
            @"identifier": TLinkAXStringValue(identifier),
            @"value": TLinkAXStringValue(value),
            @"role": TLinkAXRoleForTraits(traits),
            @"traits": @(traits),
            @"enabled": @(enabled),
            @"clickable": @(clickable),
            @"intersects_screen": @(intersectsScreen),
            @"visible": @(intersectsScreen),
            @"frame": @{
                @"x": @(frame.origin.x), @"y": @(frame.origin.y),
                @"width": @(frame.size.width), @"height": @(frame.size.height),
            },
            @"activation_point": @{
                @"x": @(point.x), @"y": @(point.y),
            },
            @"activation_point_valid": @(activationValid),
        };
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

