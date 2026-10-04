#import <Foundation/Foundation.h>

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface YTMBackgroundUpsellNotificationController : NSObject
- (void)removePendingBackgroundNotifications;
@end

%hook YTMBackgroundUpsellNotificationController
- (id)upsellNotificationTriggerOnBackground {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback") ? nil : %orig;
}
- (void)maybeScheduleBackgroundUpsellNotification {
    %orig;
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback")) [self removePendingBackgroundNotifications];
}
%end

%hook YTPlayerStatus
// YouTube Music 9.39 replaced cardboardModeActive:/blackoutActive: with
// embargoActive:embargoStatusToken: and appended playlistLoopStatus:, so the
// old 11-keyword signature no longer exists and this hook never fires.
//
// playlistLoopStatus: must be declared 'int', not 'id': its real type encoding
// is i72. Substrate's hook wrapper retains every parameter it believes is an
// object, so typing it as id made it call objc_retain() on a small integer and
// crash whenever player status was constructed -- i.e. on starting playback.
- (id)initWithExternalPlayback:(_Bool)arg1 backgroundPlayback:(_Bool)arg2 inlinePlaybackActive:(_Bool)arg3 layout:(int)arg4 userAudioOnlyModeActive:(_Bool)arg5 embargoActive:(_Bool)arg6 embargoStatusToken:(id)arg7 clipID:(id)arg8 accountLinkState:(id)arg9 muted:(_Bool)arg10 pictureInPicture:(_Bool)arg11 playlistLoopStatus:(int)arg12 {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback")) {
        arg1 = YES; arg2 = YES; arg3 = YES; arg5 = YES;
    }

    return %orig(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12);
}
%end

%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground{
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback") ? YES : %orig;
}
- (void)setIsPlayableInBackground:(BOOL)backgroundable {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback")) {
        %orig(YES);
    } else {
        %orig;
    }
}
%end

%hook YTPlaybackData
- (BOOL)isPlayableInBackground {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback") ? YES : %orig;
}
%end

%hook YTMMusicAppMetadata
- (BOOL)canPlayBackgroundableContent {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback") ? YES : %orig;
}
%end

%hook YTMMusicAppMetadataImpl
- (BOOL)canPlayBackgroundableContent {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback") ? YES : %orig;
}
%end

%hook YTLocalPlaybackController
- (BOOL)isPlaybackBackgroundable {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"backgroundPlayback") ? YES : %orig;
}
%end

%ctor {
    NSMutableDictionary *YTMUltimateDict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"]];
    NSArray *keys = @[@"YTMUltimateIsEnabled", @"backgroundPlayback", @"noAds", @"downloadAudio", @"downloadCoverImage"];
    for (NSString *key in keys) {
        if (!YTMUltimateDict[key]) {
            [YTMUltimateDict setObject:@(1) forKey:key];
            [[NSUserDefaults standardUserDefaults] setObject:YTMUltimateDict forKey:@"YTMUltimate"];
        }
    }
}
