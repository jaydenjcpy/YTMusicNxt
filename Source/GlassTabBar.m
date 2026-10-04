#import "Headers/GlassTabBar.h"
#import "Headers/LiquidGlass.h"

#import <objc/runtime.h>
#import <objc/message.h>

// Mirrors EeveeSpotifyReincarnated's GlassTabBar, retargeted from Spotify's
// NavigationUI tab bar to YouTube Music's YTPivotBarView.

static const void *kYTMUGlassTabBarKey = &kYTMUGlassTabBarKey;
// The alpha each hidden subview had before we hid it, kept per-view rather
// than in one list so a restore can never misalign if the pivot bar adds or
// recreates a subview between reveal and teardown.
static const void *kYTMUGlassOriginalAlphaKey = &kYTMUGlassOriginalAlphaKey;
// Mirrored item titles/images, used to decide whether the bar needs rebuilding.
static const void *kYTMUGlassSignatureKey = &kYTMUGlassSignatureKey;
// Item count at the point we gave up. Without this latch, exhausting the
// retries tears the overlay down, which resets the counter, so the very next
// layout pass would start the whole cycle again and churn forever.
static const void *kYTMUGlassGaveUpKey = &kYTMUGlassGaveUpKey;

static const NSInteger kYTMUMaxRetries = 40;
static const NSTimeInterval kYTMURetryDelay = 0.25;

// The stock bar is hidden as soon as this many populated items are mirrored.
static const NSUInteger kYTMUMinimumItems = 3;

// YTPivotBarItemView's real tap handler -- replaying this keeps all of YouTube's
// own navigation, analytics and long-press bookkeeping intact.
static SEL YTMUTapSelector(void) {
    static SEL selector = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        selector = NSSelectorFromString(@"doTap");
    });
    return selector;
}

#pragma mark - YouTube Music types

@interface YTPivotBarItemView : UIView
@property (nonatomic, strong, nullable, readonly) UIButton *navigationButton;
@property (nonatomic, strong, nullable, readonly) UIImageView *navigationButtonImageView;
@property (nonatomic, assign, readonly) BOOL selected;
@end

@interface YTPivotBarView : UIView
@property (nonatomic, strong, nullable, readonly) NSArray *itemViews;
@end

#pragma mark - Overlay bar

@class YTMUGlassTabBarController;

@interface YTMUGlassTabBar : UITabBar <UITabBarDelegate>
@property (nonatomic, weak, nullable) UIView *stock;
@property (nonatomic, copy, nullable) NSArray *sources;
@end

// Guards against re-entering our own bookkeeping. sync: runs from
// -layoutSubviews, and everything it does (adding a subview, resizing it,
// rebuilding items, reassigning selection) can trigger another layout pass, so
// without these the whole thing can feed back on itself.
BOOL YTMUGlassSyncInProgress = NO;
BOOL YTMUGlassSelectingProgrammatically = NO;

@implementation YTMUGlassTabBar

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    // A selection change we caused ourselves must never replay as a tap.
    if (YTMUGlassSelectingProgrammatically || YTMUGlassSyncInProgress) {
        return;
    }

    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || self.sources == nil || index >= self.sources.count) {
        return;
    }

    UIView *target = self.sources[index];
    SEL tapSelector = YTMUTapSelector();
    if ([target respondsToSelector:tapSelector]) {
        // Route the selection through YouTube's own handler rather than
        // faking a touch, so the app sees a genuine tab activation.
        void (*doTap)(id, SEL) = (void *)objc_msgSend;
        doTap(target, tapSelector);
    }

    // Our bar hides the stock one, so nothing re-syncs selection for us.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [YTMUGlassTabBarController sync:self.stock];
    });
}

@end

#pragma mark - Controller

@interface YTMUGlassTabBarController (Private)
+ (void)performSync:(nullable UIView *)stock;
@end

@implementation YTMUGlassTabBarController

+ (NSInteger)retries {
    return [objc_getAssociatedObject(self, kYTMUGlassTabBarKey) integerValue];
}

+ (void)setRetries:(NSInteger)retries {
    objc_setAssociatedObject(self, kYTMUGlassTabBarKey, @(retries), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (nullable YTMUGlassTabBar *)barForStock:(UIView *)stock create:(BOOL)create {
    YTMUGlassTabBar *bar = objc_getAssociatedObject(stock, kYTMUGlassTabBarKey);
    if (bar == nil && create) {
        bar = [[YTMUGlassTabBar alloc] initWithFrame:stock.bounds];
        bar.stock = stock;
        bar.delegate = bar;
        // Stay hidden until every item has artwork, so a half-mirrored bar is
        // never drawn on top of YouTube's real one.
        bar.hidden = YES;
        bar.alpha = 1.0;
        bar.clipsToBounds = NO;
        // The overlay can end up a touch taller than the stock strip on iPad,
        // so it must not be clipped away by its host.
        stock.clipsToBounds = NO;
        [stock addSubview:bar];
        objc_setAssociatedObject(stock, kYTMUGlassTabBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self setRetries:0];
    }
    return bar;
}

+ (CGRect)frameForStock:(UIView *)stock {
    CGRect bounds = stock.bounds;
    // Guard against a degenerate strip squashing the items.
    if (CGRectGetHeight(bounds) > 0 && CGRectGetHeight(bounds) < 50) {
        return CGRectMake(bounds.origin.x,
                          CGRectGetMidY(bounds) - 25.0,
                          bounds.size.width,
                          50.0);
    }
    return bounds;
}

+ (UIImage *_Nullable)templateImageFromItem:(UIView *)item {
    UIImageView *imageView = nil;
    if ([item respondsToSelector:NSSelectorFromString(@"navigationButtonImageView")]) {
        UIImageView *(*getImageView)(id, SEL) = (void *)objc_msgSend;
        imageView = getImageView(item, NSSelectorFromString(@"navigationButtonImageView"));
    }

    UIImage *image = imageView.image;
    if (image == nil && [item respondsToSelector:NSSelectorFromString(@"navigationButton")]) {
        UIButton *(*getButton)(id, SEL) = (void *)objc_msgSend;
        UIButton *button = getButton(item, NSSelectorFromString(@"navigationButton"));
        image = button.currentImage;
    }

    if (image == nil) {
        return nil;
    }

    // Let UITabBar do the tinting for selected/unselected.
    if (image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
        return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return image;
}

+ (NSString *_Nullable)titleFromItem:(UIView *)item {
    UILabel *label = nil;

    if ([item respondsToSelector:NSSelectorFromString(@"navigationButton")]) {
        UIButton *(*getButton)(id, SEL) = (void *)objc_msgSend;
        UIButton *button = getButton(item, NSSelectorFromString(@"navigationButton"));
        label = button.titleLabel;
    }

    NSString *title = label.text;
    if (title.length == 0) {
        title = item.accessibilityLabel;
    }
    return title.length > 0 ? title : nil;
}

+ (void)sync:(nullable UIView *)stock {
    if (stock == nil) {
        return;
    }

    // Re-entrancy: everything below can provoke another layout pass.
    if (YTMUGlassSyncInProgress) {
        return;
    }
    YTMUGlassSyncInProgress = YES;

    @try {
        [self performSync:stock];
    } @finally {
        YTMUGlassSyncInProgress = NO;
    }
}

+ (void)performSync:(nullable UIView *)stock {
    if (stock == nil) {
        return;
    }

    // Not iOS 26: leave YouTube's own tab bar completely alone.
    if (!YTMULiquidGlassAvailable()) {
        return;
    }

    if (![stock respondsToSelector:NSSelectorFromString(@"itemViews")]) {
        return;
    }

    NSArray *allItems = nil;
    @try {
        NSArray *(*getItemViews)(id, SEL) = (void *)objc_msgSend;
        allItems = getItemViews(stock, NSSelectorFromString(@"itemViews"));
    } @catch (NSException *exception) {
        return;
    }

    if (![allItems isKindOfClass:[NSArray class]]) {
        return;
    }

    // Mirror the visible items only, so hidden tabs stay hidden.
    NSMutableArray *sources = [NSMutableArray array];
    for (UIView *item in allItems) {
        if (![item isKindOfClass:[UIView class]]) {
            continue;
        }
        if (item.hidden || CGRectGetWidth(item.bounds) < 20) {
            continue;
        }
        [sources addObject:item];
    }

    if (sources.count < kYTMUMinimumItems) {
        return;
    }

    // We already tried and gave up for this exact set of tabs. Stay quiet
    // rather than rebuilding and retrying on every single layout pass. A change
    // in tab count, or toggling the setting off, clears this.
    NSNumber *gaveUpCount = objc_getAssociatedObject(stock, kYTMUGlassGaveUpKey);
    if (gaveUpCount != nil && gaveUpCount.unsignedIntegerValue == sources.count) {
        return;
    }

    YTMUGlassTabBar *bar = [self barForStock:stock create:YES];
    if (bar == nil) {
        return;
    }

    NSMutableArray<UITabBarItem *> *items = [NSMutableArray arrayWithCapacity:sources.count];
    NSMutableArray<NSString *> *signature = [NSMutableArray arrayWithCapacity:sources.count];
    NSUInteger selectedIndex = NSNotFound;

    for (NSUInteger index = 0; index < sources.count; index++) {
        UIView *item = sources[index];
        UIImage *image = [self templateImageFromItem:item];
        NSString *title = [self titleFromItem:item];

        UITabBarItem *tabItem = [[UITabBarItem alloc] initWithTitle:title image:image tag:index];
        // Same artwork both ways: UITabBar tints it by selection state itself.
        tabItem.selectedImage = image;
        [items addObject:tabItem];

        [signature addObject:title ?: @""];

        if (selectedIndex == NSNotFound &&
            [item respondsToSelector:NSSelectorFromString(@"isSelected")]) {
            BOOL (*isSelected)(id, SEL) = (void *)objc_msgSend;
            if (isSelected(item, NSSelectorFromString(@"isSelected"))) {
                selectedIndex = index;
            }
        }
    }

    bar.sources = sources;

    CGRect targetFrame = [self frameForStock:stock];
    if (!CGRectEqualToRect(bar.frame, targetFrame)) {
        bar.frame = targetFrame;
    }

    // -setItems:animated: must not run on every layout pass: UITabBarItem has
    // no value equality, so comparing the items themselves never matches, and
    // rebuilding each time resets selection and re-triggers the delegate --
    // which replays taps and re-enters this method. Compare a signature of the
    // mirrored state instead, and only rebuild when that actually differs.
    NSArray<NSString *> *currentSignature = objc_getAssociatedObject(bar, kYTMUGlassSignatureKey);
    if (currentSignature == nil || ![currentSignature isEqualToArray:signature]) {
        objc_setAssociatedObject(bar, kYTMUGlassSignatureKey, signature,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        YTMUGlassSelectingProgrammatically = YES;
        [bar setItems:items animated:NO];
        YTMUGlassSelectingProgrammatically = NO;
    }

    if (selectedIndex != NSNotFound && selectedIndex < bar.items.count &&
        bar.selectedItem != bar.items[selectedIndex]) {
        YTMUGlassSelectingProgrammatically = YES;
        bar.selectedItem = bar.items[selectedIndex];
        YTMUGlassSelectingProgrammatically = NO;
    }

    // Every item needs artwork before we are willing to hide the real bar.
    BOOL complete = YES;
    for (UITabBarItem *item in bar.items) {
        if (item.image == nil) {
            complete = NO;
            break;
        }
    }

    if (complete) {
        [self setRetries:0];
        objc_setAssociatedObject(stock, kYTMUGlassGaveUpKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self reveal:bar over:stock];
    } else if ([self retries] < kYTMUMaxRetries) {
        [self setRetries:[self retries] + 1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kYTMURetryDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self sync:stock];
        });
    } else {
        // Gave up -- restore the stock bar rather than leaving a blank strip,
        // and latch so we do not immediately start another retry cycle.
        objc_setAssociatedObject(stock, kYTMUGlassGaveUpKey, @(sources.count),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self teardown:stock];
    }
}

+ (void)reveal:(YTMUGlassTabBar *)bar over:(UIView *)stock {
    if (bar.superview != stock) {
        [stock addSubview:bar];
    }
    [stock bringSubviewToFront:bar];

    for (UIView *subview in stock.subviews) {
        if (subview == bar) {
            continue;
        }
        if (subview.alpha != 0.0 && objc_getAssociatedObject(subview, kYTMUGlassOriginalAlphaKey) == nil) {
            objc_setAssociatedObject(subview, kYTMUGlassOriginalAlphaKey,
                                     @(subview.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        subview.alpha = 0.0;
        subview.userInteractionEnabled = NO;
    }

    bar.hidden = NO;
    if (bar.alpha != 1.0) {
        bar.alpha = 0.0;
        [UIView animateWithDuration:0.2 animations:^{
            bar.alpha = 1.0;
        }];
    }
}

+ (void)teardown:(nullable UIView *)stock {
    if (stock == nil) {
        return;
    }

    YTMUGlassTabBar *bar = objc_getAssociatedObject(stock, kYTMUGlassTabBarKey);
    if (bar == nil) {
        return;
    }

    [bar removeFromSuperview];

    // Restore every subview we ever dimmed, whatever has happened to the
    // hierarchy in the meantime.
    for (UIView *subview in stock.subviews) {
        NSNumber *originalAlpha = objc_getAssociatedObject(subview, kYTMUGlassOriginalAlphaKey);
        if (originalAlpha != nil) {
            subview.alpha = originalAlpha.doubleValue;
            subview.userInteractionEnabled = YES;
            objc_setAssociatedObject(subview, kYTMUGlassOriginalAlphaKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    [bar setItems:@[] animated:NO];
    bar.sources = nil;

    // Force a rebuild if the overlay is ever shown again.
    objc_setAssociatedObject(bar, kYTMUGlassSignatureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(stock, kYTMUGlassTabBarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stock, kYTMUGlassGaveUpKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self setRetries:0];
}

@end