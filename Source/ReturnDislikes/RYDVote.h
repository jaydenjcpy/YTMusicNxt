// Vote lookup and number formatting, ported from
// PoomSmart/Return-YouTube-Dislikes (Vote.h).

#import <Foundation/Foundation.h>

#define RYD_FETCHING @"⌛"
#define RYD_FAILED @"❌"

NSNumber *RYDGetLikeData(NSDictionary<NSString *, NSNumber *> *data);
NSNumber *RYDGetDislikeData(NSDictionary<NSString *, NSNumber *> *data);
NSString *RYDGetNormalizedLikes(NSNumber *likeNumber, NSString *error);
NSString *RYDGetNormalizedDislikes(NSNumber *dislikeNumber, NSString *error);

void RYDGetVoteFromVideoWithHandler(NSCache<NSString *, NSDictionary *> *cache,
                                    NSString *videoId,
                                    int retryCount,
                                    void (^handler)(NSDictionary *data, NSString *error));