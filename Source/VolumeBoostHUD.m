// Volume boost HUD.
//
// Vendored from VolumeBoostYT by vasirakcalgux (https://github.com/irum0320/VolumeBoostYT),
// MIT License, Copyright (c) 2024 vasirakcalgux. See VolumeBoost.x.

#import "VolumeBoostHUD.h"

@interface VolumeBoostHUD ()
@property (nonatomic, strong) UILabel *textLabel;
@end

@implementation VolumeBoostHUD

+ (instancetype)sharedHUD {
    static VolumeBoostHUD *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 200, 40)];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
        self.layer.cornerRadius = 20;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        self.alpha = 0.0;

        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:label];
        self.textLabel = label;
    }
    return self;
}

- (void)showWithValue:(float)value {
    self.textLabel.text = [NSString stringWithFormat:@"App Vol: %.0f%%", value * 100];

    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
            if (window) {
                break;
            }
        }
    }

    if (!window) {
        return;
    }

    if (self.superview != window) {
        [window addSubview:self];
    }

    self.center = CGPointMake(CGRectGetMidX(window.bounds), 80);
    [window bringSubviewToFront:self];

    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1.0;
    }];

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(hide)
                                               object:nil];
    [self performSelector:@selector(hide) withObject:nil afterDelay:1.5];
}

- (void)hide {
    [UIView animateWithDuration:0.3
        animations:^{
            self.alpha = 0.0;
        }
        completion:^(BOOL finished) {
            if (finished) {
                [self removeFromSuperview];
            }
        }];
}

@end