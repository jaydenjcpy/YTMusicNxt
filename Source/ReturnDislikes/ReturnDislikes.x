// Return-YouTube-Music-Dislikes -- show real dislike counts in YouTube Music.
//
// Ported from PoomSmart/Return-YouTube-Music-Dislikes (Tweak.x) and its
// dependency PoomSmart/Return-YouTube-Dislikes, both GPL-3.0,
// Copyright (c) PoomSmart.
//
//   https://github.com/PoomSmart/Return-YouTube-Music-Dislikes
//   https://github.com/PoomSmart/Return-YouTube-Dislikes
//
// YouTube Music hides dislike counts but still fetches the like/dislike action
// bar for videos, so the counts are fetched from the Return YouTube Dislike
// database and written over the "Dislike" label.
//
// Changes from upstream:
//   * Settings live in the YTMusicUltimate dictionary and default to off, so
//     nothing is sent to the RYD database until the user asks for it.
//   * The upstream Settings.x is dropped: it builds its UI from
//     YTMSettingsSectionItem's itemWithTitle:... and switchItemWithTitle:...
//     factories, which YouTube Music 9.39 no longer has. The equivalent three
//     switches are in Player options instead.
//   * YTLikeService is gone in 9.39 (YTLikeServiceImpl is the live class), so
//     only the Impl hook is installed. Upstream installs both.
//   * Handles a nil video ID, which upstream would send to the API as
//     "/votes?videoId=(null)".

#import <UIKit/UIKit.h>

#import "../Headers/ASDisplayNode.h"
#import "../Headers/YTILikeButtonRenderer.h"
#import "../Headers/MDCButton.h"
#import "../Headers/YTMNowPlayingViewController.h"
#import "RYDAPI.h"
#import "RYDSettings.h"
#import "RYDVote.h"

// Declared here rather than importing Source/Headers/YTMActionRowView.h because
// that header uses include paths relative to Source/, which do not resolve from
// this directory. The like/dislike buttons are read by KVC, not by ivar.
@interface YTMActionRowView : UIView
@end

static NSCache<NSString *, NSDictionary *> *RYDCache = nil;

// Set while we ask ELM to build a text node for the cloned dislike element, so
// that classForElement: returns ELMTextNode instead of whatever node type the
// element's own class implies. Same flag upstream uses.
static int RYDOverrideNodeCreation = 0;

__strong ELMTextNode *RYDLikeTextNode = nil;
__strong ELMTextNode *RYDDislikeTextNode = nil;
__strong NSMutableAttributedString *RYDMutableDislikeText = nil;

static BOOL RYDIsVideoScrollableActionBar(ASCollectionView *collectionView) {
    return [collectionView.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"];
}

// Reads the video ID through KVC. Both objects are Protobuf messages whose
// properties the protobuf runtime resolves dynamically, so a direct accessor
// call is not safe to assume and KVC works whether it is a getter or an ivar.
static NSString *RYDVideoIdFromTarget(id target) {
    if (target == nil) return nil;

    id videoId = nil;
    @try {
        videoId = [target valueForKey:@"videoId"];
    } @catch (id exception) {
        return nil;
    }
    return [videoId isKindOfClass:[NSString class]] ? videoId : nil;
}

static NSString *RYDVideoIdFromRenderer(YTILikeButtonRenderer *renderer) {
    if (renderer == nil) return nil;

    id target = nil;
    @try {
        target = [renderer valueForKey:@"target"];
    } @catch (id exception) {
        return nil;
    }
    return RYDVideoIdFromTarget(target);
}

static NSString *RYDGetVideoId(ASDisplayNode *containerNode) {
    YTMNowPlayingViewController *vc = (YTMNowPlayingViewController *)[containerNode closestViewController];
    if (![vc isKindOfClass:%c(YTMNowPlayingViewController)]) return nil;
    return RYDVideoIdFromRenderer([vc valueForKey:@"likeButtonRenderer"]);
}

%hook YTMActionRowView

- (void)updateLikeDislikeButtonWithRenderer:(YTILikeButtonRenderer *)renderer {
    %orig;
    if (!RYDEnabled()) return;

    NSString *videoId = RYDVideoIdFromRenderer(renderer);
    if (videoId.length == 0) return;

    MDCButton *likeButton = [self valueForKey:@"_likeButton"];
    MDCButton *dislikeButton = [self valueForKey:@"_dislikeButton"];
    [dislikeButton setTitle:RYD_FETCHING forState:UIControlStateNormal];
    [dislikeButton ytm_sizeToFitWithSize:1];
    [self setNeedsLayout];

    RYDGetVoteFromVideoWithHandler(RYDCache, videoId, RYDMaxRetryCount, ^(NSDictionary *data, NSString *error) {
        if (RYDExactLikeNumber()) {
            NSString *likeText = RYDGetNormalizedLikes(RYDGetLikeData(data), error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [likeButton setTitle:likeText forState:UIControlStateNormal];
                [likeButton ytm_sizeToFitWithSize:1];
                [self setNeedsLayout];
            });
        }

        NSString *dislikeText = RYDGetNormalizedDislikes(RYDGetDislikeData(data), error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [dislikeButton setTitle:dislikeText forState:UIControlStateNormal];
            [dislikeButton ytm_sizeToFitWithSize:1];
            [self setNeedsLayout];
        });
    });
}

%end

%hook ASCollectionView

- (ELMCellNode *)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    ELMCellNode *node = %orig;
    if (!RYDIsVideoScrollableActionBar(self) || !RYDEnabled()) return node;

    _ASCollectionViewCell *likeDislikeCell = [self.subviews firstObject];
    ASDisplayNode *containerNode = [likeDislikeCell node];
    NSString *videoId = RYDGetVideoId(containerNode);
    if (videoId == nil) return node;

    int pairMode = -1;
    BOOL isDislikeButtonModified = NO;

    // Walk down the single-child Yoga chain to the row holding like + dislike.
    do {
        containerNode = [containerNode.yogaChildren firstObject];
        if (containerNode == nil) return node;
        if (containerNode.yogaChildren.count == 2)
            containerNode = [containerNode.yogaChildren objectAtIndex:1];
    } while (containerNode.yogaChildren.count == 1);

    ELMContainerNode *likeNode = (ELMContainerNode *)[containerNode.yogaChildren firstObject];
    if (likeNode == nil) return node;

    if (likeNode.yogaChildren.count == 2) {
        ELMContainerNode *dislikeNode = (ELMContainerNode *)[containerNode.yogaChildren lastObject];
        isDislikeButtonModified = dislikeNode.yogaChildren.count == 2;

        id targetNode = [likeNode.yogaChildren objectAtIndex:1];
        RYDLikeTextNode = (ELMTextNode *)targetNode;
        if (isDislikeButtonModified) {
            RYDDislikeTextNode = (ELMTextNode *)[dislikeNode.yogaChildren objectAtIndex:1];
        } else {
            // No dislike text node yet: clone the like node's element so ELM
            // builds one for us, then keep its attributes so colours and font
            // match the like count.
            id elementContext = [RYDLikeTextNode valueForKey:@"_context"];
            RYDOverrideNodeCreation = 2;
            RYDDislikeTextNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:RYDLikeTextNode.element
                                                                   materializationContext:&elementContext];
            RYDOverrideNodeCreation = 0;
            RYDMutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:RYDLikeTextNode.attributedText];
            RYDDislikeTextNode.attributedText = RYDMutableDislikeText;
            [dislikeNode addYogaChild:RYDDislikeTextNode];
            [dislikeNode.view addSubview:RYDDislikeTextNode.view];
            pairMode = 0;
        }
    } else {
        RYDDislikeTextNode = (ELMTextNode *)[likeNode.yogaChildren objectAtIndex:1];
        if (![RYDDislikeTextNode isKindOfClass:%c(ELMTextNode)]) return node;

        RYDMutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:RYDDislikeTextNode.attributedText];
        RYDMutableDislikeText.mutableString.string = RYD_FETCHING;
        RYDDislikeTextNode.attributedText = RYDMutableDislikeText;
    }

    BOOL shouldFetchVote = RYDExactLikeNumber() || !isDislikeButtonModified;
    if (!shouldFetchVote) return node;

    RYDGetVoteFromVideoWithHandler(RYDCache, videoId, RYDMaxRetryCount, ^(NSDictionary *data, NSString *error) {
        if (RYDExactLikeNumber() && error == nil && RYDLikeTextNode != nil) {
            NSString *likeCount = RYDGetNormalizedLikes(RYDGetLikeData(data), nil);
            if (likeCount != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSMutableAttributedString *mutableLikeText = [[NSMutableAttributedString alloc] initWithAttributedString:RYDLikeTextNode.attributedText];
                    mutableLikeText.mutableString.string = likeCount;
                    RYDLikeTextNode.attributedText = mutableLikeText;
                    RYDLikeTextNode.accessibilityLabel = likeCount;
                });
            }
        }

        NSString *dislikeCount = RYDGetNormalizedDislikes(RYDGetDislikeData(data), error);
        // The like/dislike text node is rebuilt on every cell dequeue, so only
        // touch ours if it is still the one on screen.
        if (isDislikeButtonModified || RYDDislikeTextNode == nil) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *dislikeString = (pairMode == 0)
                ? [NSString stringWithFormat:@"  %@ ", dislikeCount]
                : dislikeCount;
            RYDMutableDislikeText.mutableString.string = dislikeString;
            RYDDislikeTextNode.attributedText = RYDMutableDislikeText;
            RYDDislikeTextNode.accessibilityLabel = dislikeCount;
        });
    });

    return node;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    // Dark/light switch rebuilds the like text node's attributes, which would
    // wipe our dislike text unless it is refreshed from it.
    if (!RYDIsVideoScrollableActionBar(self) || !RYDEnabled() || RYDDislikeTextNode == nil) return;

    NSString *dislikeText = RYDDislikeTextNode.attributedText.string;
    RYDMutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:RYDLikeTextNode.attributedText];
    RYDMutableDislikeText.mutableString.string = dislikeText;
    RYDDislikeTextNode.attributedText = RYDMutableDislikeText;
}

%end

%hook ELMNodeFactory

- (Class)classForElement:(id)element materializationContext:(const void *)context {
    if (RYDOverrideNodeCreation == 2) return %c(ELMTextNode);
    return %orig;
}

%end

%hook YTLikeServiceImpl

- (void)makeRequestWithStatus:(YTLikeStatus)likeStatus
                       target:(YTILikeTarget *)target
          clickTrackingParams:(id)clickTrackingParams
          queueContextParams:(id)queueContextParams
                requestParams:(id)requestParams
               responseBlock:(id)responseBlock
                  errorBlock:(id)errorBlock {
    if (RYDEnabled() && RYDVoteSubmissionEnabled()) {
        RYDSendVote(RYDVideoIdFromTarget(target), likeStatus);
    }
    %orig;
}

%end

%ctor {
    RYDCache = [NSCache new];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:RYDDidResetUserIDKey]) {
        [defaults setBool:YES forKey:RYDDidResetUserIDKey];
        // Older builds generated base64 user IDs that the API rejects.
        NSString *userID = [defaults stringForKey:RYDUserIDKey];
        if ([userID containsString:@"+"] || [userID containsString:@"/"]) {
            [defaults removeObjectForKey:RYDUserIDKey];
            [defaults removeObjectForKey:RYDRegistrationConfirmedKey];
        }
    }
}