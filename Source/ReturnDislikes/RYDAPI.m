// Return YouTube Dislike API client.
//
// Ported from PoomSmart/Return-YouTube-Dislikes (API.x), GPL-3.0,
// Copyright (c) PoomSmart, https://github.com/PoomSmart/Return-YouTube-Dislikes.
// The API/puzzle code is itself ported to Objective-C from the Return YouTube
// Dislike browser extension.
//
// Changes: ARC instead of MRR, liblog's HBLogDebug replaced by RYDLog, the
// upstream TweakSettings accessors replaced by the YTMusicUltimate settings
// dictionary, and the API_URL build define replaced by a constant.

#import <CommonCrypto/CommonDigest.h>

#import "RYDAPI.h"
#import "RYDSettings.h"

static NSString *RYDGetUserID(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:RYDUserIDKey];
}

static BOOL RYDIsRegistered(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:RYDRegistrationConfirmedKey];
}

// The Return YouTube Dislike API wants +1 for a like and -1 for a dislike,
// which is not how YouTube encodes YTLikeStatus (0 = like, 1 = dislike,
// 2 = neutral).
static int RYDToAPILikeStatus(YTLikeStatus likeStatus) {
    switch (likeStatus) {
        case YTLikeStatusLike:
            return 1;
        case YTLikeStatusDislike:
            return -1;
        default:
            return 0;
    }
}

static const char *RYDCharset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

// Ported to objc from RYD browser extension
static NSString *RYDGenerateUserID(void) {
    NSString *existingID = RYDGetUserID();
    if (existingID) return existingID;

    char userID[36 + 1];
    for (int i = 0; i < 36; ++i)
        userID[i] = RYDCharset[arc4random_uniform(62)];
    userID[36] = '\0';

    NSString *result = [NSString stringWithUTF8String:userID];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:result forKey:RYDUserIDKey];
    return result;
}

// Ported to objc from RYD browser extension
static int RYDCountLeadingZeroes(uint8_t *hash) {
    int zeroes = 0;
    int value = 0;
    for (int i = 0; i < CC_SHA512_DIGEST_LENGTH; i++) {
        value = hash[i];
        if (value == 0)
            zeroes += 8;
        else {
            int count = 1;
            if (value >> 4 == 0) {
                count += 4;
                value <<= 4;
            }
            if (value >> 6 == 0) {
                count += 2;
                value <<= 2;
            }
            zeroes += count - (value >> 7);
            break;
        }
    }
    return zeroes;
}

// Ported to objc from RYD browser extension
static NSString *RYDBtoa(NSString *input) {
    NSMutableString *output = [NSMutableString string];
    for (int i = 0; i < input.length; i += 3) {
        int groupsOfSix[4] = { -1, -1, -1, -1 };
        unichar ci = [input characterAtIndex:i];
        groupsOfSix[0] = ci >> 2;
        groupsOfSix[1] = (ci & 0x03) << 4;
        if (input.length > i + 1) {
            unichar ci1 = [input characterAtIndex:i + 1];
            groupsOfSix[1] |= ci1 >> 4;
            groupsOfSix[2] = (ci1 & 0x0f) << 2;
        }
        if (input.length > i + 2) {
            unichar ci2 = [input characterAtIndex:i + 2];
            groupsOfSix[2] |= ci2 >> 6;
            groupsOfSix[3] = ci2 & 0x3f;
        }
        for (int j = 0; j < 4; ++j) {
            if (groupsOfSix[j] == -1)
                [output appendString:@"="];
            else
                [output appendFormat:@"%c", RYDCharset[groupsOfSix[j]]];
        }
    }
    return output;
}

void RYDFetch(NSString *endpoint,
              NSString *method,
              NSDictionary *body,
              void (^dataHandler)(NSDictionary *data),
              BOOL (^responseCodeHandler)(NSUInteger responseCode),
              void (^networkErrorHandler)(void),
              void (^dataErrorHandler)(void)) {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", RYD_API_URL, endpoint]];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    urlRequest.HTTPMethod = method;

    if (body) {
        [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingPrettyPrinted error:&error];
        if (error) {
            RYDLog(@"fetch() error serialising body: %@", error);
            if (dataErrorHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    dataErrorHandler();
                });
            }
            return;
        }
        urlRequest.HTTPBody = data;
    } else {
        [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    }

    [[session dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSUInteger responseCode = [httpResponse statusCode];

        if (responseCodeHandler) {
            if (!responseCodeHandler(responseCode)) return;
        }

        if (error || responseCode != 200) {
            RYDLog(@"fetch() error requesting %@ (%lu)", endpoint, (unsigned long)responseCode);
            if (networkErrorHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    networkErrorHandler();
                });
            }
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *myData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:&jsonError];
        if (jsonError) {
            RYDLog(@"fetch() error decoding response: %@", jsonError);
            if (dataErrorHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    dataErrorHandler();
                });
            }
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            dataHandler(myData);
        });
    }] resume];
}

// Ported to objc from RYD browser extension
static NSString *RYDSolvePuzzle(NSDictionary *data) {
    NSString *solution = nil;
    NSString *challenge = data[@"challenge"];
    int difficulty = [data[@"difficulty"] intValue];
    NSData *cd = [[NSData alloc] initWithBase64EncodedString:challenge options:0];
    NSString *decoded = [[NSString alloc] initWithData:cd encoding:NSASCIIStringEncoding];
    if (!decoded) return nil;

    uint8_t c[decoded.length];
    char *buffer = (char *)calloc(20, sizeof(char));
    if (!buffer) return nil;
    uint32_t *uInt32View = (uint32_t *)buffer;

    for (int i = 0; i < decoded.length; ++i)
        c[i] = [decoded characterAtIndex:i];

    int maxCount = (1 << difficulty) * 3;
    // Upstream only copies the first 16 challenge bytes into the 20 byte buffer;
    // guarding the index keeps a malformed challenge from reading past c[].
    int copyCount = MIN(16, (int)decoded.length);
    for (int i = 0; i < copyCount; ++i)
        buffer[i + 4] = c[i];

    for (int i = 0; i < maxCount; ++i) {
        uInt32View[0] = i;
        uint8_t hash[CC_SHA512_DIGEST_LENGTH] = {0};
        CC_SHA512(buffer, 20, hash);
        if (RYDCountLeadingZeroes(hash) >= difficulty) {
            char chars[4] = { buffer[0], buffer[1], buffer[2], buffer[3] };
            solution = RYDBtoa([[NSString alloc] initWithBytes:chars length:4 encoding:NSASCIIStringEncoding]);
            break;
        }
    }

    free(buffer);
    return solution;
}

// Ported to objc from RYD browser extension
static void RYDRegisterUser(void) {
    NSString *userId = RYDGenerateUserID();
    NSString *puzzleEndpoint = [NSString stringWithFormat:@"/puzzle/registration?userId=%@", userId];

    RYDFetch(puzzleEndpoint, @"GET", nil, ^(NSDictionary *data) {
        NSString *solution = RYDSolvePuzzle(data);
        if (!solution) return;

        RYDFetch(puzzleEndpoint, @"POST", @{ @"solution": solution }, ^(NSDictionary *data) {
            if ([data isKindOfClass:[NSNumber class]] && ![(NSNumber *)data boolValue]) return;

            if (!RYDIsRegistered()) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:RYDRegistrationConfirmedKey];
            }
        }, NULL, ^() {}, ^() {});
    }, NULL, ^() {}, ^() {});
}

// Ported to objc from RYD browser extension
static void _RYDSendVote(NSString *videoId, YTLikeStatus likeStatus, int retryCount) {
    if (retryCount <= 0) return;

    NSString *userId = RYDGetUserID();
    if (!userId || !RYDIsRegistered()) {
        RYDRegisterUser();
        return;
    }

    RYDFetch(@"/interact/vote", @"POST", @{
        @"userId": userId,
        @"videoId": videoId,
        @"value": @(RYDToAPILikeStatus(likeStatus))
    }, ^(NSDictionary *data) {
        NSString *solution = RYDSolvePuzzle(data);
        if (!solution) return;

        RYDFetch(@"/interact/confirmVote", @"POST", @{
            @"userId": userId,
            @"videoId": videoId,
            @"solution": solution
        }, ^(NSDictionary *data) {}, ^BOOL(NSUInteger responseCode) {
            return YES;
        }, ^() {}, ^() {});
    }, ^BOOL(NSUInteger responseCode) {
        if (responseCode == 401) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                RYDRegisterUser();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    _RYDSendVote(videoId, likeStatus, retryCount - 1);
                });
            });
            return NO;
        }
        return YES;
    }, ^() {}, ^() {});
}

void RYDSendVote(NSString *videoId, YTLikeStatus likeStatus) {
    _RYDSendVote(videoId, likeStatus, RYDMaxRetryCount);
}