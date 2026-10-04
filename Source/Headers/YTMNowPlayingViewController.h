#import "YTMWatchViewController.h"
#import "YTILikeButtonRenderer.h"

@interface YTMNowPlayingViewController : UIViewController
@property (nonatomic, weak, readwrite) YTMWatchViewController *parentViewController;
@property (nonatomic, strong, readonly) YTILikeButtonRenderer *likeButtonRenderer;

- (void)didTapNextButton;
- (void)didTapPrevButton;
- (void)didTapSeekForwardButton;
- (void)didTapSeekBackwardButton;
- (void)longPressPrev:(UILongPressGestureRecognizer *)gesture;
- (void)longPressNext:(UILongPressGestureRecognizer *)gesture;
@end