// Picture in Picture for YouTube Music videos.
//
// Ported from PoomSmart/YouMusicPiP (Tweak.x), MIT License,
// Copyright (c) 2021 - 2024 PoomSmart,
// https://github.com/PoomSmart/YouMusicPiP. That in turn is based on
// PoomSmart/YouPiP for the YouTube app.
//
// Upstream makes YouTube Music start PiP when you leave the app while a video
// is playing. As shipped against 9.39 it cannot work: four of the things it
// hooks no longer exist. What changed, and what this port does instead:
//
//   * MLPIPController is now MLPIPControllerImpl.
//   * YTBackgroundabilityPolicy and YTBackgroundabilityPolicyImpl are gone.
//     Upstream forced the "_playableInPiPByUserSettings" flag on them; here the
//     equivalent gates are YTPlayerPIPController's own isPictureInPictureAllowed
//     and isEligibleForPictureInPicture.
//   * YTPlayerViewController's -appWillResignActive: is gone, and
//     -canInvokePictureInPicture is now -canEnablePictureInPicture. The
//     "app is leaving" callback that matters now lives on YTPlayerPIPController
//     as -appWillResignActive, with no argument, so that is what is hooked.
//   * YTHotConfig no longer exposes mediaHotConfig, so upstream's trick of
//     flipping enablePictureInPicture on the server config has nothing to flip.
//     The client-side gates above are used instead. enablePictureInPicture is
//     also not a property of YTIIosMediaHotConfig any more, so writing it would
//     have raised an unrecognised-selector exception.
//   * YTIPlayabilityStatus lost -hasPictureInPicture.
//   * MLDefaultPlayerViewFactory lost the three ...ForVideo: variants.
//
// The toggle is "Picture in picture" in Player options and defaults to off,
// because turning it on changes how video is rendered even when PiP is never
// used.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>

#import "../Headers/MusicPiP.h"

#define YTMUPiPKey @"pictureInPicture"

static BOOL YTMUPiPEnabled(void) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[@"YTMUltimateIsEnabled"] boolValue] && [YTMUltimateDict[YTMUPiPKey] boolValue];
}

// Set while asking whether PiP is available. YouTube refuses PiP for live
// playback, and a live music stream should not block the check.
static BOOL YTMSingleVideoIsLivePlaybackOverride = NO;

#pragma mark - Helpers

static id YTMUPiPControllerFromPlayer(YTPlayerPIPController *player) {
    // YTPlayerPIPController keeps the MediaHub controller in _pipController.
    id pip = nil;
    @try {
        pip = [player valueForKey:@"_pipController"];
    } @catch (id exception) {
        return nil;
    }
    return pip;
}

static void YTMUStartPictureInPicture(YTPlayerPIPController *player) {
    id pip = YTMUPiPControllerFromPlayer(player);
    if (pip == nil) return;

    if ([pip respondsToSelector:@selector(activatePiPController)]) {
        [pip activatePiPController];
    }

    // The AVPlayer controller inside MediaHub is what actually shows the video.
    id avpip = nil;
    @try {
        avpip = [pip valueForKey:@"_pictureInPictureController"];
    } @catch (id exception) {
        return;
    }

    // Called dynamically: the object behind _pictureInPictureController is
    // MediaHub's own subclass, not AVPictureInPictureController itself.
    SEL possible = NSSelectorFromString(@"isPictureInPicturePossible");
    if ([avpip respondsToSelector:possible]) {
        BOOL (*isPossible)(id, SEL) = (BOOL (*)(id, SEL))[avpip methodForSelector:possible];
        if (isPossible(avpip, possible)) {
            void (*start)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
            start(avpip, NSSelectorFromString(@"startPictureInPicture"));
        }
    }
}

// Forces the AVPlayer render view, which is the only one YouTube can hand to
// AVPlayerViewController for PiP. The hamplayer views are not PiP capable.
static void YTMUForceAVPlayerRenderView(id playerConfig) {
    if (playerConfig == nil) return;
    if (![playerConfig respondsToSelector:@selector(setRenderViewType:)]) return;
    [playerConfig setRenderViewType:6];
}

#pragma mark - PiP support

%hook AVPictureInPictureController

+ (BOOL)isPictureInPictureSupported {
    return YES;
}

- (void)setCanStartPictureInPictureAutomaticallyFromInline:(BOOL)canStartFromInline {
    // Automatic PiP is what makes leaving the app bring up the video window;
    // letting YouTube turn it off would undo the whole tweak.
    %orig(YTMUPiPEnabled() ? YES : canStartFromInline);
}

%end

%hook MLPIPControllerImpl

- (BOOL)pictureInPictureSupported {
    return YTMUPiPEnabled() ? YES : %orig;
}

%end

%hook YTIPlayabilityStatus

- (BOOL)isPlayableInBackground {
    return YTMUPiPEnabled() ? YES : %orig;
}

- (BOOL)isPlayableInPictureInPicture {
    return YTMUPiPEnabled() ? YES : %orig;
}

%end

%hook YTPlayerPIPController

- (BOOL)canEnablePictureInPicture {
    if (!YTMUPiPEnabled()) return %orig;

    YTMSingleVideoIsLivePlaybackOverride = YES;
    %orig;
    YTMSingleVideoIsLivePlaybackOverride = NO;
    return YES;
}

- (BOOL)isEligibleForPictureInPicture {
    return YTMUPiPEnabled() ? YES : %orig;
}

- (BOOL)isPictureInPictureAllowed {
    return YTMUPiPEnabled() ? YES : %orig;
}

- (void)appWillResignActive {
    %orig;
    if (!YTMUPiPEnabled()) return;

    YTMSingleVideoIsLivePlaybackOverride = YES;
    YTMUStartPictureInPicture(self);
    YTMSingleVideoIsLivePlaybackOverride = NO;
}

%end

%hook YTSingleVideo

- (BOOL)isLivePlayback {
    return YTMSingleVideoIsLivePlaybackOverride ? NO : %orig;
}

%end

%hook MLDefaultPlayerViewFactory

- (id)AVPlayerViewForPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    YTMUForceAVPlayerRenderView(playerConfig);
    return %orig;
}

- (id)hamPlayerViewForPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    YTMUForceAVPlayerRenderView(playerConfig);
    return %orig;
}

- (BOOL)canUsePlayerView:(id)playerView forPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    YTMUForceAVPlayerRenderView(playerConfig);
    return %orig;
}

%end

%ctor {
    %init;
}