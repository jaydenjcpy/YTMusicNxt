#import <UIKit/UIKit.h>

@interface MDCButton : UIButton

// Used by the likes/dislikes row to re-measure after the button title changes.
- (void)ytm_sizeToFitWithSize:(NSInteger)size;

@end