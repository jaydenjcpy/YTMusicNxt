#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers/LiquidGlass.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface YTMNavigationBarView : UIView
@end

@interface QTMButton : UIButton
@property (nonatomic, copy, readwrite) NSString *accessibilityIdentifier;
@end

@interface YTMSortFilterButton : UIButton
@end

%hook QTMButton
- (void)layoutSubviews {
    %orig;
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideHistoryButton")) {
        if ([self.accessibilityIdentifier isEqualToString:@"id.navigation.history.button"]) {
            self.hidden = YES;
        }
    }
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideCastButton")) {
        if ([self.accessibilityIdentifier isEqualToString:@"id.mdx.playbackroute.button"]) {
            self.hidden = YES;
        }
    }

    // Liquid Glass (iOS 26+). A no-op on older systems, and reversing it keeps
    // the original background so the toggle can be switched back off.
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"liquidGlassButtons")) {
        YTMULiquidGlassApply(self);
    } else {
        YTMULiquidGlassRemove(self);
    }
}
%end

%hook YTMNavigationBarView
- (void)layoutSubviews {
    %orig;

    NSArray *subviews = [self subviews];

    UIView *sortFilterButton = nil;
    for (UIView *subview in subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"YTMSortFilterButton")]) {
            sortFilterButton = subview;
            break;
        }
    }

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"hideFilterButton")) {
        if (sortFilterButton != nil) {
            [sortFilterButton removeFromSuperview];
        }
    }
}
%end
