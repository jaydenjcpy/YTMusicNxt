#import "RYDSettings.h"

static BOOL RYDSetting(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    // Every option in this tweak is opt-in, so an absent key means off.
    return [YTMUltimateDict[key] boolValue];
}

BOOL RYDEnabled(void) {
    return RYDSetting(RYDEnabledKey);
}

BOOL RYDExactLikeNumber(void) {
    return RYDSetting(RYDExactLikeKey);
}

BOOL RYDUseRawData(void) {
    return RYDSetting(RYDUseRawDataKey);
}

BOOL RYDVoteSubmissionEnabled(void) {
    return RYDSetting(RYDVoteSubmissionKey);
}

void RYDLog(NSString *format, ...) {
    // Upstream logs through liblog's HBLogDebug at every step of the API dance.
    // Nothing here is worth filling a user's device log with, so this is a no-op
    // that still type checks the format string at compile time.
    (void)format;
}