// Return YouTube Dislike API client, ported from PoomSmart/Return-YouTube-Dislikes.

#import <Foundation/Foundation.h>

#import "../Headers/YTILikeButtonRenderer.h"

#define RYD_API_URL @"https://returnyoutubedislikeapi.com"

void RYDFetch(NSString *endpoint,
              NSString *method,
              NSDictionary *body,
              void (^dataHandler)(NSDictionary *data),
              BOOL (^responseCodeHandler)(NSUInteger responseCode),
              void (^networkErrorHandler)(void),
              void (^dataErrorHandler)(void));

// Sends the user's like/dislike to the RYD database. Only called when the user
// has explicitly turned vote submission on.
void RYDSendVote(NSString *videoId, YTLikeStatus likeStatus);