#import <UIKit/UIKit.h>
#import "YTPlayerResponse.h"

@interface YTPlayerViewController : UIViewController
// YTMusic 9.39 dropped -playerResponse in favour of -contentPlayerResponse. The
// name below is what the tweak hooks against; see Downloading.x for the
// runtime fallback chain that keeps older/premium builds working too.
@property (nonatomic, assign, readonly) YTPlayerResponse *contentPlayerResponse;
@property (nonatomic, assign, readonly) YTPlayerResponse *playerResponse;
@property (readonly, nonatomic) NSString *contentVideoID;
@property (nonatomic, assign, readonly) CGFloat currentVideoTotalMediaTime;
// Not a YouTube property: SponsorBlock.x adds it via %property so that the
// %new -skipSegment helper below can reach it. Declared here because Logos emits
// %new methods outside the @interface extension Logos would otherwise use.
@property (nonatomic, strong) NSMutableDictionary *sponsorBlockValues;


- (void)seekToTime:(CGFloat)time;
- (NSString *)currentVideoID;
- (CGFloat)currentVideoMediaTime;
- (void)skipSegment;
@end
