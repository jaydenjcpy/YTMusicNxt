// Volume boost HUD.
//
// Vendored from VolumeBoostYT by vasirakcalgux (https://github.com/irum0320/VolumeBoostYT),
// MIT License, Copyright (c) 2024 vasirakcalgux. Only the view was reused; the
// original tweak's YouTube-specific settings injection was dropped because it
// targets classes that do not exist in YouTube Music. See VolumeBoost.x.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VolumeBoostHUD : UIView

+ (instancetype)sharedHUD;
- (void)showWithValue:(float)value;
- (void)hide;

@end

NS_ASSUME_NONNULL_END