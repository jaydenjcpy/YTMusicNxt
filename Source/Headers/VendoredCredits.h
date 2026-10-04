// Single source of truth for third-party tweaks vendored into YTMusicUltimate.
//
// Every tweak ported in from another project must be listed here, and the same
// entries must appear in CREDITS.md and in the CREDITS.txt shipped inside
// YTMusicUltimate.bundle. Keeping the list here means the in-app credits can
// never drift from the ones the licences require.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTMUVendoredCredit : NSObject

// Display name of the upstream tweak, e.g. @"VolumeBoostYT".
@property (nonatomic, copy, readonly) NSString *name;
// Author of the upstream tweak, e.g. @"vasirakcalgux".
@property (nonatomic, copy, readonly) NSString *author;
// Short name of the upstream licence, e.g. @"MIT".
@property (nonatomic, copy, readonly) NSString *license;
// Upstream repository URL.
@property (nonatomic, copy, readonly) NSString *url;
// One-line summary of what we changed when porting it.
@property (nonatomic, copy, readonly) NSString *changes;

+ (NSArray<YTMUVendoredCredit *> *)allCredits;

// Lines suitable for showing in the settings footer, e.g.
// @"VolumeBoostYT by vasirakcalgux (MIT)".
+ (NSArray<NSString *> *)footerLines;

@end

NS_ASSUME_NONNULL_END