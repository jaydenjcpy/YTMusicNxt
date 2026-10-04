// Volume boost -- up to 2000% app volume, adjustable by an edge swipe.
//
// Vendored from VolumeBoostYT by vasirakcalgux (https://github.com/irum0320/VolumeBoostYT),
// MIT License, Copyright (c) 2024 vasirakcalgux.
//
// What was kept: the AVFoundation volume hooks and the UIWindow edge gesture,
// both of which are app-agnostic.
//
// What was dropped: the original tweak's settings injection, which hooks
// YTSettingsGroupData / YTAppSettingsPresentationData / YTSettingsSectionItemManager.
// Those are YouTube-only classes that do not exist in YouTube Music, which is
// why the upstream tweak's settings never appear here. This build is driven by
// the "Volume boost" switch in YTMusicUltimate > Player options instead.
//
// Unlike the original, this defaults to OFF: amplifying to 20x unprompted on
// first install is a nasty surprise on shared hardware.

#import "VolumeBoostHUD.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kVolumeBoostKey = @"volumeBoost";

// Set to 1 to remember the volume across app restarts, 0 to reset to 100% on launch.
#define ENABLE_VOLUME_PERSISTENCE 0

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

static BOOL IsVolumeBoostEnabled(void) {
    if (!YTMU(@"YTMUltimateIsEnabled")) {
        return NO;
    }
    return YTMU(kVolumeBoostKey);
}

#if ENABLE_VOLUME_PERSISTENCE
static NSString *const kCustomVolumeMultiplierKey = @"CustomVolumeMultiplier";
#else
static float currentVolumeMultiplier = 1.0f;
#endif

// Weak table of live audio renderers, so a volume change can be re-applied to
// each of them without walking the view hierarchy.
static NSHashTable *activeRenderers = nil;

static void RegisterRenderer(id renderer) {
    if (activeRenderers == nil) {
        activeRenderers = [NSHashTable weakObjectsHashTable];
    }
    if (renderer != nil) {
        [activeRenderers addObject:renderer];
    }
}

static float GetCustomVolumeMultiplier(void) {
#if ENABLE_VOLUME_PERSISTENCE
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kCustomVolumeMultiplierKey] == nil) {
        return 1.0f;
    }
    return [defaults floatForKey:kCustomVolumeMultiplierKey];
#else
    return currentVolumeMultiplier;
#endif
}

static float GetLogarithmicAudioMultiplier(void) {
    float m = GetCustomVolumeMultiplier();
    if (m <= 1.0f) {
        return m;
    }
    // The UI runs from 1.0 to 20.0 (2000%). Map that linearly onto an exponent
    // so the top of the range reaches 200x physical amplitude.
    return powf(200.0f, (m - 1.0f) / 19.0f);
}

static void NotifyVolumeChange(void) {
    for (id renderer in [activeRenderers allObjects]) {
        if ([renderer respondsToSelector:@selector(setVolume:)]) {
            // Re-apply a base of 1.0, which the hooks below multiply again.
            [renderer setVolume:1.0f];
        }
    }
}

static void SetCustomVolumeMultiplier(float multiplier) {
    if (multiplier < 0.0f) {
        multiplier = 0.0f;
    }
    if (multiplier > 20.0f) {
        multiplier = 20.0f;
    }

#if ENABLE_VOLUME_PERSISTENCE
    [[NSUserDefaults standardUserDefaults] setFloat:multiplier forKey:kCustomVolumeMultiplierKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
#else
    currentVolumeMultiplier = multiplier;
#endif

    NotifyVolumeChange();
}

// ---------------------------------------------------------
// AVFoundation hooks
//
// Each audio stack is hooked because they respond differently to a volume
// above 1.0. A volume of 1.0 passes through untouched, so this is inert while
// the multiplier is at unity or the feature is off.
// ---------------------------------------------------------

%hook AVPlayer

- (instancetype)init {
    id result = %orig;
    RegisterRenderer(result);
    return result;
}

- (void)setVolume:(float)volume {
    RegisterRenderer(self);
    if (IsVolumeBoostEnabled()) {
        volume = volume * GetLogarithmicAudioMultiplier();
    }
    %orig(volume);
}
%end

%hook AVAudioPlayerNode

- (instancetype)init {
    id result = %orig;
    RegisterRenderer(result);
    return result;
}

- (void)setVolume:(float)volume {
    RegisterRenderer(self);
    if (IsVolumeBoostEnabled()) {
        volume = volume * GetLogarithmicAudioMultiplier();
    }
    %orig(volume);
}
%end

%hook AVAudioPlayer

- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError {
    id result = %orig(url, outError);
    RegisterRenderer(result);
    return result;
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)outError {
    id result = %orig(data, outError);
    RegisterRenderer(result);
    return result;
}

- (void)setVolume:(float)volume {
    RegisterRenderer(self);
    if (IsVolumeBoostEnabled()) {
        volume = volume * GetLogarithmicAudioMultiplier();
    }
    %orig(volume);
}
%end

%hook AVSampleBufferAudioRenderer

- (instancetype)init {
    id result = %orig;
    RegisterRenderer(result);
    return result;
}

- (void)setVolume:(float)volume {
    RegisterRenderer(self);
    if (IsVolumeBoostEnabled()) {
        volume = volume * GetLogarithmicAudioMultiplier();
    }
    %orig(volume);
}
%end

// ---------------------------------------------------------
// Edge gesture
//
// Tracked inside -[UIWindow sendEvent:] rather than with an overlay view, so
// YouTube's own fullscreen rotation and layout behave exactly as they do
// without the tweak.
// ---------------------------------------------------------

static float gestureStartMultiplier = 1.0f;
static BOOL possibleVolumeGesture = NO;
static BOOL isTrackingVolumeGesture = NO;
static CGPoint initialTouchPoint;

%hook UIWindow

- (void)sendEvent:(UIEvent *)event {
    // Disabled: stay completely out of the way, including touch handling.
    if (!IsVolumeBoostEnabled()) {
        %orig(event);
        return;
    }

    // External displays and other scenes are not ours to touch.
    if (self.screen != [UIScreen mainScreen]) {
        %orig(event);
        return;
    }

    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) {
        %orig(event);
        return;
    }

    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];

    switch (touch.phase) {
        case UITouchPhaseBegan: {
            CGFloat screenWidth = CGRectGetWidth(self.bounds);
            if (location.x >= screenWidth - 25.0f) {
                possibleVolumeGesture = YES;
                isTrackingVolumeGesture = NO;
                initialTouchPoint = location;
                return;
            }
            break;
        }

        case UITouchPhaseMoved: {
            if (possibleVolumeGesture) {
                CGFloat dx = initialTouchPoint.x - location.x;  // positive when moving inwards
                CGFloat dy = (CGFloat)fabs(location.y - initialTouchPoint.y);

                // Require a deliberate inward swipe before committing, so an
                // ordinary tap near the edge is not stolen.
                if (dx > 15.0f && dx > dy) {
                    isTrackingVolumeGesture = YES;
                    possibleVolumeGesture = NO;
                    initialTouchPoint = location;
                    gestureStartMultiplier = GetCustomVolumeMultiplier();
                    [[VolumeBoostHUD sharedHUD] showWithValue:gestureStartMultiplier];
                    return;
                }

                if (dy > 20.0f || dx < -10.0f) {
                    possibleVolumeGesture = NO;
                } else {
                    return;
                }
            }

            if (isTrackingVolumeGesture) {
                CGFloat translationY = location.y - initialTouchPoint.y;
                float deltaMultiplier = (float)(-translationY / 30.0f);
                float newMultiplier = gestureStartMultiplier + deltaMultiplier;

                if (newMultiplier < 0.0f) {
                    newMultiplier = 0.0f;
                }
                if (newMultiplier > 20.0f) {
                    newMultiplier = 20.0f;
                }

                SetCustomVolumeMultiplier(newMultiplier);
                [[VolumeBoostHUD sharedHUD] showWithValue:newMultiplier];
                return;
            }
            break;
        }

        case UITouchPhaseEnded:
        case UITouchPhaseCancelled: {
            if (possibleVolumeGesture) {
                possibleVolumeGesture = NO;
                return;
            }
            if (isTrackingVolumeGesture) {
                isTrackingVolumeGesture = NO;
                [[VolumeBoostHUD sharedHUD] performSelector:@selector(hide)
                                                 withObject:nil
                                                 afterDelay:1.0];
                return;
            }
            break;
        }

        default:
            break;
    }

    %orig(event);
}
%end