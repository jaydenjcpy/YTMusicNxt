#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// iOS 26 "Liquid Glass" applied at runtime, resolved by name rather than by
// symbol.
//
// The theos build compiles against its own iOS 16.5 SDK (see TARGET in the
// Makefile), which predates UIGlassEffect / UICornerConfiguration entirely, so
// UIKit's headers cannot be used here. Instead every iOS 26 class and selector
// below is looked up with NSClassFromString / NSSelectorFromString and invoked
// through objc_msgSend. That keeps the tweak free of any link-time dependency
// on UIKit 26 symbols, which matters because YouTubeMusic's own minimum is
// iOS 16.0 -- referencing UIGlassEffect directly would fail to load there.

typedef NS_ENUM(NSInteger, YTMUGlassEffectStyle) {
    // Mirrors UIGlassEffectStyleRegular / UIGlassEffectStyleClear.
    YTMUGlassEffectStyleRegular = 0,
    YTMUGlassEffectStyleClear = 1,
};

/// YES only on iOS 26+ where UIGlassEffect is genuinely present.
FOUNDATION_EXPORT BOOL YTMULiquidGlassAvailable(void);

/// A fresh UIGlassEffect, or nil when running on anything older than iOS 26.
FOUNDATION_EXPORT UIVisualEffect *_Nullable YTMULiquidGlassEffect(YTMUGlassEffectStyle style,
                                                                  UIColor *_Nullable tintColor);

/// Gives `host` a Liquid Glass capsule background.
///
/// Reuses a blur view the host already carries when it has one -- swapping the
/// effect in place, so no extra view or layout is needed. Otherwise a pane is
/// inserted behind the host's content. Calling this repeatedly is cheap and
/// idempotent.
///
/// Returns NO below iOS 26, where the caller should leave the view alone.
FOUNDATION_EXPORT BOOL YTMULiquidGlassApply(UIView *host);

/// Undoes YTMULiquidGlassApply, restoring the host's original background.
FOUNDATION_EXPORT void YTMULiquidGlassRemove(UIView *host);

NS_ASSUME_NONNULL_END