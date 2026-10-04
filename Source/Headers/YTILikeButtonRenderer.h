// Minimal YouTube interfaces needed by the Return-YouTube-Music-Dislikes port.
//
// Trimmed from PoomSmart/YouTubeHeader to only what Source/ReturnDislikes
// actually calls, so that this fork does not need to vendor a header repo.
// Presence of every selector here was verified against the YouTube Music 9.39
// binary: YTILikeButtonRenderer and YTILikeTarget are Protobuf messages whose
// properties are synthesised accessors, ELMTextNode inherits attributedText
// from ASTextNode, and accessibilityLabel comes from ASDisplayNode.

#import <Foundation/Foundation.h>

// These values are not guesses: they come from PoomSmart/YouTubeHeader's
// YTLikeStatus.h, and the 9.39 binary encodes the parameter as int ("i16" in
// makeRequestWithStatus:target:...), so the underlying type is int too.
typedef NS_ENUM(int, YTLikeStatus) {
    YTLikeStatusLike = 0,
    YTLikeStatusDislike = 1,
    YTLikeStatusNeutral = 2
};

// YTILikeTarget and YTILikeButtonRenderer are Protobuf messages: their
// properties are listed in the class's property list but have no accessor in
// its method list, because the protobuf runtime resolves them dynamically.
// Read them through KVC rather than assuming a compiled getter.
@interface YTILikeTarget : NSObject

@property (nonatomic, copy, readonly) NSString *videoId;
@property (nonatomic, copy, readonly) NSString *playlistId;

@end

@interface YTILikeButtonRenderer : NSObject

@property (nonatomic, strong, readonly) YTILikeTarget *target;

@end