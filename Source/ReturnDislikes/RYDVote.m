// Vote lookup and number formatting.
//
// Ported from PoomSmart/Return-YouTube-Dislikes (Vote.x), GPL-3.0,
// Copyright (c) PoomSmart, https://github.com/PoomSmart/Return-YouTube-Dislikes.
// The K/M/B suffix formatting upstream uses below iOS 13 is from
// https://gist.github.com/danpashin/5951706a6aa25748a7faa1acd5c1db8b.
//
// Changes: ARC, RYDLog instead of HBLogDebug, the settings accessors now read
// the YTMusicUltimate dictionary, and an NSUInteger video ID length check that
// upstream does not have (it would run [videoId length] on a nil ID).
//
// Upstream abbreviates counts with ICU's UNUM_DECIMAL_COMPACT_SHORT on iOS 13+
// so "1234567" becomes "1.2M" in the user's own locale. Theos' iPhoneOS SDK
// does not ship the ICU headers, so this port always uses the K/M/B suffixes
// below instead, which are the same values without locale-aware separators.

#import "RYDAPI.h"
#import "RYDSettings.h"
#import "RYDVote.h"

static NSNumber *RYDLikeData(NSDictionary<NSString *, NSNumber *> *data) {
    // Is it a good idea to return only the likes from the RYD users?
    return data[@"likes"];
}

static NSNumber *RYDDislikeData(NSDictionary<NSString *, NSNumber *> *data) {
    NSNumber *dislikes = data[@"dislikes"];
    if (RYDUseRawData()) {
        NSNumber *rawDislikes = data[@"rawDislikes"];
        if (rawDislikes != (id)[NSNull null])
            return rawDislikes;
    }
    return dislikes;
}

NSNumber *RYDGetLikeData(NSDictionary<NSString *, NSNumber *> *data) {
    return RYDLikeData(data);
}

NSNumber *RYDGetDislikeData(NSDictionary<NSString *, NSNumber *> *data) {
    return RYDDislikeData(data);
}

// Upstream's getXPointYFormat: 1234 -> "1.2K", but 1200 -> "1.0K".
static NSString *RYDGetXPointYFormat(NSString *count, unichar suffix) {
    unichar firstInt = [count characterAtIndex:0];
    unichar secondInt = [count characterAtIndex:1];
    if (secondInt == '0')
        return [NSString stringWithFormat:@"%c%c", firstInt, suffix];
    return [NSString stringWithFormat:@"%c.%c%c", firstInt, secondInt, suffix];
}

static NSString *RYDGetNormalizedNumber(NSNumber *number, BOOL exact, NSString *error) {
    if (!number) return RYD_FAILED;
    if (exact) return [NSNumberFormatter localizedStringFromNumber:number numberStyle:NSNumberFormatterDecimalStyle];

    NSString *count = [number stringValue];
    NSUInteger digits = count.length;
    if (digits <= 3) return count;                                // 0 - 999
    if (digits == 4) return RYDGetXPointYFormat(count, 'K');      // 1000 - 9999
    if (digits <= 6) return [NSString stringWithFormat:@"%@K", [count substringToIndex:digits - 3]];
    if (digits <= 9) return [NSString stringWithFormat:@"%@M", [count substringToIndex:digits - 6]];
    if (digits <= 12) return [NSString stringWithFormat:@"%@B", [count substringToIndex:digits - 9]];
    return [NSString stringWithFormat:@"%@T", [count substringToIndex:digits - 12]];
}

NSString *RYDGetNormalizedLikes(NSNumber *likeNumber, NSString *error) {
    return RYDGetNormalizedNumber(likeNumber, RYDExactLikeNumber(), error);
}

NSString *RYDGetNormalizedDislikes(NSNumber *dislikeNumber, NSString *error) {
    return RYDGetNormalizedNumber(dislikeNumber, NO, error);
}

void RYDGetVoteFromVideoWithHandler(NSCache<NSString *, NSDictionary *> *cache,
                                    NSString *videoId,
                                    int retryCount,
                                    void (^handler)(NSDictionary *data, NSString *error)) {
    if (retryCount <= 0) return;

    // Upstream formats /votes?videoId=%@ with a nil ID and then fetches
    // "/votes?videoId=(null)", which the API answers with a 400.
    if (videoId.length == 0) {
        handler(nil, RYD_FAILED);
        return;
    }

    NSDictionary *data = [cache objectForKey:videoId];
    if (data) {
        handler(data, nil);
        return;
    }

    RYDFetch([NSString stringWithFormat:@"/votes?videoId=%@", videoId], @"GET", nil, ^(NSDictionary *data) {
        [cache setObject:data forKey:videoId];
        handler(data, nil);
    }, ^BOOL(NSUInteger responseCode) {
        if (responseCode == 502 || responseCode == 503) {
            handler(nil, @"CON"); // connection error
            return NO;
        }
        if (responseCode == 401 || responseCode == 403 || responseCode == 407) {
            handler(nil, @"AUTH"); // unauthorized
            return NO;
        }
        if (responseCode == 429) {
            handler(nil, @"RL"); // rate limit
            return NO;
        }
        if (responseCode == 404) {
            handler(nil, @"NULL"); // non-existing video
            return NO;
        }
        if (responseCode == 400) {
            handler(nil, @"INV"); // malformed video
            return NO;
        }
        return YES;
    }, ^() {
        handler(nil, RYD_FAILED);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            RYDGetVoteFromVideoWithHandler(cache, videoId, retryCount - 1, handler);
        });
    }, ^() {
        handler(nil, RYD_FAILED);
    });
}