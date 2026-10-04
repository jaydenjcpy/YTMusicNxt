// Settings bridge for the Return-YouTube-Music-Dislikes port.
//
// Upstream keeps its preferences in its own NSUserDefaults keys so that the
// tweak can be shipped as a separate injected dylib. Here it lives in the
// YTMusicUltimate dictionary like every other option, so the three switches
// appear in Player options next to Volume boost.

#import <Foundation/Foundation.h>

// Keys inside the "YTMUltimate" defaults dictionary.
#define RYDEnabledKey @"returnDislikes"
#define RYDExactLikeKey @"returnDislikesExactLike"
#define RYDUseRawDataKey @"returnDislikesRawData"
#define RYDVoteSubmissionKey @"returnDislikesVoteSubmission"

// Keys upstream keeps in NSUserDefaults directly, kept because they hold the
// anonymous RYD account rather than a preference.
#define RYDUserIDKey @"RYD-USER-ID"
#define RYDRegistrationConfirmedKey @"RYD-USER-REGISTERED"
#define RYDDidResetUserIDKey @"RYD-DID-RESET-USER-ID"

#define RYDMaxRetryCount 3

BOOL RYDEnabled(void);
BOOL RYDExactLikeNumber(void);
BOOL RYDUseRawData(void);
BOOL RYDVoteSubmissionEnabled(void);

// Upstream logs a lot through liblog's HBLogDebug. Nothing here logs: a failed
// vote lookup is not interesting enough to be worth the user's device log.
void RYDLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);