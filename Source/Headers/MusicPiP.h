// Minimal interfaces for the Picture in Picture port.
//
// Trimmed from PoomSmart/YouTubeHeader and PoomSmart/YouMusicPiP's Header.h.
// Only the selectors hooked in Source/MusicPiP/YouMusicPiP.x are declared, and
// each one was checked against the YouTube Music 9.39 binary for both existence
// and type encoding.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// YouTube's own picture-in-picture controller. Note that 9.39 spells the
// "user is leaving the app" callback -appWillResignActive with no argument,
// where the YouTube app's controller takes one.
@interface YTPlayerPIPController : NSObject

@property (nonatomic, readonly) BOOL isPictureInPictureActive;
@property (nonatomic, readonly) BOOL isPictureInPictureAllowed;
@property (nonatomic, readonly) BOOL isPictureInPicturePossible;

- (BOOL)canEnablePictureInPicture;
- (BOOL)isEligibleForPictureInPicture;
- (void)maybeTogglePictureInPicture;

// -appWillResignActive
@end

// The MediaHub layer underneath it. Renamed from MLPIPController to
// MLPIPControllerImpl at some point before 9.39.
@interface MLPIPControllerImpl : NSObject

@property (nonatomic, readonly) BOOL pictureInPictureActive;
@property (nonatomic, readonly) BOOL pictureInPictureSupported;

- (void)activatePiPController;
- (void)deactivatePiPController;
- (void)stopPictureInPicture;

@end

@interface MLVideoDecoderFactory : NSObject
@end

@interface MLInnerTubePlayerConfig : NSObject
@end

@interface MLDefaultPlayerViewFactory : NSObject

- (id)AVPlayerViewForPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig;
- (id)hamPlayerViewForPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig;
- (BOOL)canUsePlayerView:(id)playerView forPlayerConfig:(MLInnerTubePlayerConfig *)playerConfig;

@end

@interface YTIPlayabilityStatus : NSObject

@property (nonatomic, readonly) BOOL isPlayableInBackground;
@property (nonatomic, readonly) BOOL isPlayableInPictureInPicture;

@end

@interface YTSingleVideo : NSObject

@property (nonatomic, readonly) BOOL isLivePlayback;

@end

// Protobuf message holding the renderer choice. renderViewType 6 is the
// AVPlayer-backed view, which is the one AVPlayerViewController can put on
// screen for PiP.
@interface YTIHamplayerConfig : NSObject
@property (nonatomic) int renderViewType;
@end

// The server config that actually decides whether YouTube offers picture in
// picture at all. Both properties below exist on 9.39; the enablePictureInPicture
// property that older builds of YouMusicPiP set does not, which is why those
// versions are worth re-porting rather than copying.
@interface YTIIosMediaHotConfig : NSObject

@property (nonatomic) BOOL enablePipForNonPremiumUsers;
@property (nonatomic) BOOL enablePipForNonBackgroundableContent;

@end

@interface YTHotConfig : NSObject

@property (nonatomic, strong, readonly) YTIIosMediaHotConfig *mediaHotConfig;

@end