#import "Headers/YTMBrowseViewController.h"
#import "Headers/YTPivotBarView.h"
#import "Headers/YTIPivotBarSupportedRenderers.h"
#import "Headers/YTAssetLoader.h"
#import "Headers/GlassTabBar.h"
#import "Prefs/YTMDownloads.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

%hook YTMPivotBarItemStyle
- (UIImage *)pivotBarItemIconImageWithIconType:(int)type color:(UIColor *)color useNewIcons:(BOOL)isNew selected:(BOOL)isSelected {
    if (type == 1 || type == 2) {
        NSString *imageName = isSelected ? @"icons/downloads_selected" : @"icons/downloads";
        if (type == 2) imageName = isSelected ? @"icons/downloads_cairo_selected" : @"icons/downloads_cairo";

        YTAssetLoader *al = [[%c(YTAssetLoader) alloc] initWithBundle:NSBundle.ytmu_defaultBundle];
        return [al imageNamed:imageName];
    }

    return %orig;
}
%end

// https://gist.github.com/BandarHL/dce564ab717bed93d479fe849d654c75
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    if (YTMU(@"YTMUltimateIsEnabled") && !YTMU(@"hideDownloadsTab")) {
        YTIIcon *ytmuIcon = [%c(YTIIcon) new];
        ytmuIcon.iconType = 1;

        if ([[renderer description] containsString:@"TAB_BOOKMARK"]) {
            ytmuIcon.iconType = 2;
        }

        YTIBrowseEndpoint *ytmuBrowseEndpoint = [%c(YTIBrowseEndpoint) new];
        ytmuBrowseEndpoint.browseId = @"FEytmu_downloads";

        YTICommand *ytmuCommand = [%c(YTICommand) new];
        ytmuCommand.browseEndpoint = ytmuBrowseEndpoint;

        YTIAccessibilityData *ytmuData = [%c(YTIAccessibilityData) new];
        ytmuData.label = LOC(@"DOWNLOADS");

        YTIAccessibilitySupportedDatas *ytmuAccessibility = [%c(YTIAccessibilitySupportedDatas) new];
        ytmuAccessibility.accessibilityData = ytmuData;

        YTIPivotBarItemRenderer *barItem = [[%c(YTIPivotBarItemRenderer) alloc] init];
        barItem.pivotIdentifier = @"FEytmu_downloads";
        barItem.targetId = @"pivot-ytmu-downloads";
        barItem.title = [%c(YTIFormattedString) formattedStringWithString:LOC(@"DOWNLOADS")];
        barItem.icon = ytmuIcon;
        barItem.navigationEndpoint = ytmuCommand;
        barItem.accessibility = ytmuAccessibility;

        YTIPivotBarSupportedRenderers *ytmuRenderer = [%c(YTIPivotBarSupportedRenderers) new];
        ytmuRenderer.pivotBarItemRenderer = barItem;

        [renderer.itemsArray addObject:ytmuRenderer];
    }

    %orig(renderer);
}
%end

// Liquid Glass tab bar (iOS 26+): overlays a real UITabBar, which iOS 26 styles
// as glass natively, and replays taps onto the stock YTPivotBarItemViews. The
// controller only hides the real bar once every item has artwork, so a failure
// here degrades to YouTube's own tab bar rather than a dead strip.
%hook YTPivotBarView
- (void)layoutSubviews {
    %orig;

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"liquidGlassTabBar")) {
        [YTMUGlassTabBarController sync:self];
    } else {
        [YTMUGlassTabBarController teardown:self];
    }
}
%end

%hook YTMBrowseViewController
- (void)viewDidLoad {
    %orig;

    if (YTMU(@"YTMUltimateIsEnabled") && !YTMU(@"hideDownloadsTab")) {
        YTICommand *navEndpoint = nil;

        if (class_getInstanceVariable([self class], "_navEndpoint") != NULL) {
            navEndpoint = [self valueForKey:@"_navEndpoint"];
        }

        if (class_getInstanceVariable([self class], "_navigationEndpoint") != NULL) {
            navEndpoint = [self valueForKey:@"_navigationEndpoint"];
        }

        if (navEndpoint) {
            if ([navEndpoint.browseEndpoint.browseId isEqualToString:@"FEytmu_downloads"]) {
                YTMDownloads *ytmuDownloadsVC = [[YTMDownloads alloc] init];
                [self addChildViewController:ytmuDownloadsVC];
                [ytmuDownloadsVC.view setFrame:CGRectMake(0.0f, 0.0f, self.view.frame.size.width, self.view.frame.size.height)];
                [self.view addSubview:ytmuDownloadsVC.view];
                [self.view endEditing:YES];
                [ytmuDownloadsVC didMoveToParentViewController:self];
            }
        }
    }
}
%end