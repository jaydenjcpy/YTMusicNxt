#import "Headers/LiquidGlass.h"

#import <objc/message.h>
#import <objc/runtime.h>

// Associated keys for the pane we install and the background we replaced, so
// the treatment can be reversed when the user turns the toggle back off.
static const void *kYTMUGlassPaneKey = &kYTMUGlassPaneKey;
static const void *kYTMUGlassOriginalBackgroundKey = &kYTMUGlassOriginalBackgroundKey;
static const void *kYTMUGlassCornersAppliedKey = &kYTMUGlassCornersAppliedKey;

static Class YTMUGlassEffectClass(void) {
    return NSClassFromString(@"UIGlassEffect");
}

BOOL YTMULiquidGlassAvailable(void) {
    if (@available(iOS 26.0, *)) {
        return YTMUGlassEffectClass() != Nil;
    }
    return NO;
}

UIVisualEffect *YTMULiquidGlassEffect(YTMUGlassEffectStyle style, UIColor *tintColor) {
    if (!YTMULiquidGlassAvailable()) {
        return nil;
    }

    Class glassClass = YTMUGlassEffectClass();
    SEL styleSel = NSSelectorFromString(@"effectWithStyle:");
    if (![glassClass respondsToSelector:styleSel]) {
        return nil;
    }

    UIVisualEffect *(*makeEffect)(Class, SEL, NSInteger) = (void *)objc_msgSend;
    UIVisualEffect *effect = makeEffect(glassClass, styleSel, (NSInteger)style);
    if (effect == nil) {
        return nil;
    }

    if (tintColor != nil) {
        SEL tintSel = NSSelectorFromString(@"setTintColor:");
        if ([effect respondsToSelector:tintSel]) {
            void (*setTint)(id, SEL, UIColor *) = (void *)objc_msgSend;
            setTint(effect, tintSel, tintColor);
        }
    }

    return effect;
}

// The capsule configuration is a single shared object. Building a fresh one on
// every call would allocate needlessly, and this runs from -layoutSubviews.
static id YTMUCapsuleCornerConfiguration(void) {
    static id configuration = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        Class cornerClass = NSClassFromString(@"UICornerConfiguration");
        if (cornerClass == Nil) {
            return;
        }

        SEL capsuleSel = NSSelectorFromString(@"capsuleConfiguration");
        if (![cornerClass respondsToSelector:capsuleSel]) {
            return;
        }

        id (*makeCapsule)(Class, SEL) = (void *)objc_msgSend;
        configuration = makeCapsule(cornerClass, capsuleSel);
    });

    return configuration;
}

// Rounds a view into a capsule. UICornerConfiguration also only exists on iOS
// 26, so the configuration object is built through the runtime as well.
//
// Assigning cornerConfiguration: can trigger another layout pass, so each view
// is only ever configured once; YTMULiquidGlassRemove clears the flag if the
// view needs reshaping later.
static BOOL YTMUApplyCapsuleCorners(UIView *view) {
    if ([objc_getAssociatedObject(view, kYTMUGlassCornersAppliedKey) boolValue]) {
        return YES;
    }

    id configuration = YTMUCapsuleCornerConfiguration();
    if (configuration == nil) {
        return NO;
    }

    SEL setCornerSel = NSSelectorFromString(@"setCornerConfiguration:");
    if (![view respondsToSelector:setCornerSel]) {
        return NO;
    }

    void (*setCorner)(id, SEL, id) = (void *)objc_msgSend;
    setCorner(view, setCornerSel, configuration);

    objc_setAssociatedObject(view, kYTMUGlassCornersAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

BOOL YTMULiquidGlassApply(UIView *host) {
    if (!YTMULiquidGlassAvailable()) {
        return NO;
    }

    UIVisualEffectView *pane = objc_getAssociatedObject(host, kYTMUGlassPaneKey);
    if (pane != nil) {
        // Already installed by us -- just keep it sized and behind the content.
        if (pane.superview != host) {
            [host insertSubview:pane atIndex:0];
        } else if (host.subviews.firstObject != pane) {
            [host sendSubviewToBack:pane];
        }
        pane.frame = host.bounds;
        return YES;
    }

    // Cheap path: if the view already carries a blur, swap its effect in place.
    // This is the approach used by EeveeSpotifyReincarnated -- real glass with
    // no additional views and nothing to lay out.
    for (UIView *subview in host.subviews) {
        if (![subview isKindOfClass:[UIVisualEffectView class]]) {
            continue;
        }

        UIVisualEffectView *blur = (UIVisualEffectView *)subview;
        if (![blur.effect isKindOfClass:YTMUGlassEffectClass()]) {
            blur.effect = YTMULiquidGlassEffect(YTMUGlassEffectStyleRegular, nil);
        }
        YTMUApplyCapsuleCorners(blur);
        blur.userInteractionEnabled = NO;
        blur.accessibilityElementsHidden = YES;

        if (objc_getAssociatedObject(host, kYTMUGlassOriginalBackgroundKey) == nil) {
            objc_setAssociatedObject(host, kYTMUGlassOriginalBackgroundKey,
                                    host.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        host.backgroundColor = [UIColor clearColor];
        return YES;
    }

    // Otherwise install our own pane behind the host's content.
    UIVisualEffect *effect = YTMULiquidGlassEffect(YTMUGlassEffectStyleRegular, nil);
    if (effect == nil) {
        return NO;
    }

    UIVisualEffectView *newPane = [[UIVisualEffectView alloc] initWithEffect:effect];
    newPane.userInteractionEnabled = NO;
    newPane.accessibilityElementsHidden = YES;
    newPane.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    YTMUApplyCapsuleCorners(newPane);

    [host insertSubview:newPane atIndex:0];
    objc_setAssociatedObject(host, kYTMUGlassPaneKey, newPane, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (objc_getAssociatedObject(host, kYTMUGlassOriginalBackgroundKey) == nil) {
        objc_setAssociatedObject(host, kYTMUGlassOriginalBackgroundKey,
                                host.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    host.backgroundColor = [UIColor clearColor];
    return YES;
}

void YTMULiquidGlassRemove(UIView *host) {
    UIVisualEffectView *pane = objc_getAssociatedObject(host, kYTMUGlassPaneKey);
    if (pane != nil) {
        [pane removeFromSuperview];
        objc_setAssociatedObject(host, kYTMUGlassPaneKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // A blur we repointed at glass is ours to restore.
    for (UIView *subview in host.subviews) {
        if (![subview isKindOfClass:[UIVisualEffectView class]]) {
            continue;
        }

        UIVisualEffectView *blur = (UIVisualEffectView *)subview;
        if ([blur.effect isKindOfClass:YTMUGlassEffectClass()]) {
            blur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            objc_setAssociatedObject(blur, kYTMUGlassCornersAppliedKey,
                                    nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    UIColor *original = objc_getAssociatedObject(host, kYTMUGlassOriginalBackgroundKey);
    if (original != nil) {
        host.backgroundColor = original;
        objc_setAssociatedObject(host, kYTMUGlassOriginalBackgroundKey,
                                nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}