#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// A real UITabBar layered over YouTube Music's YTPivotBarView, so that iOS 26
// renders the tab bar with its own native Liquid Glass treatment instead of the
// stock pivot bar.
//
// This is the approach EeveeSpotifyReincarnated takes on its overhaul branch:
// UITabBar is the one view iOS 26 automatically styles as glass, and Spotify's
// tab bar is a plain custom view, so they overlay a genuine UITabBar, hide the
// stock bar, and replay taps onto its hidden item views.
//
// Unlike Spotify, though, YouTube Music needs no synthesis: YTPivotBarView
// already carries a blurView and its own liquidGlassEffect, which is why this
// file does not build any glass effect itself -- UITabBar supplies it.
//
// The stock bar is only ever hidden once the overlay is fully populated (every
// item has an image). Until then, and permanently if that never happens, the
// original tab bar stays visible and fully interactive, so a failure here can
// never leave the user without working tabs.

@interface YTMUGlassTabBarController : NSObject

/// Rebuilds/refreshes the overlay to match the stock pivot bar's current items.
+ (void)sync:(nullable UIView *)stock;

/// Removes the overlay and restores the stock tab bar exactly as it was.
+ (void)teardown:(nullable UIView *)stock;

@end

NS_ASSUME_NONNULL_END