#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FFMpegDownloader.h"
#import "Headers/YTUIResources.h"
#import "Headers/YTMActionSheetController.h"
#import "Headers/YTMActionRowView.h"
#import "Headers/YTIPlayerOverlayRenderer.h"
#import "Headers/YTIPlayerOverlayActionSupportedRenderers.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTPlayerView.h"
#import "Headers/YTIThumbnailDetails_Thumbnail.h"
#import "Headers/YTIFormatStream.h"
#import "Headers/YTIThumbnailDetails.h"
#import "Headers/YTAlertView.h"
#import "Headers/ELMNodeController.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

// Every network hop the download flow performs gets a deadline. The old code used
// -dataWithContentsOfURL: (no timeout, synchronous) for both the HLS manifest and
// the cover art, so a stalled connection froze the UI thread forever and the
// download never finished nor reported anything.
static const NSTimeInterval YTMURequestTimeout = 20.0;
static const NSTimeInterval YTMUResourceTimeout = 180.0;
static const NSUInteger YTMUMaxManifestBytes = 4 * 1024 * 1024;
static const NSUInteger YTMUMaxImageBytes = 12 * 1024 * 1024;

static NSURLSession *YTMUSession(void) {
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = YTMURequestTimeout;
        config.timeoutIntervalForResource = YTMUResourceTimeout;
        config.HTTPAdditionalHeaders = @{@"User-Agent": @"com.google.ios.youtubemusic/19.29.1 (iPhone16,2; U; CPU iOS 18_3 like Mac OS X)"};
        session = [NSURLSession sessionWithConfiguration:config];
    });
    return session;
}

@interface UIView ()
- (UIViewController *)_viewControllerForAncestor;
@end

@interface ELMTouchCommandPropertiesHandler : NSObject
- (void)downloadAudio:(YTPlayerViewController *)playerViewController;
- (void)downloadCoverImage:(YTPlayerViewController *)playerViewController;
- (NSString *)getURLFromManifest:(NSURL *)manifest;
- (YTPlayerResponse *)resolvePlayerResponseFrom:(id)object;
- (void)fetchCoverDataFromURL:(NSURL *)url fileName:(NSString *)fileName;
@end

// Media titles come straight from the server, so they can contain path separators,
// colons or newlines that make the cover write fail silently (which reads to the
// user as a download that finished but has no artwork).
static NSString *YTMUSanitizeFileName(NSString *name) {
    if (name.length == 0) return @"unknown";
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:\0"];
    NSString *cleaned = [[name componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"_"];
    cleaned = [cleaned stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    cleaned = [cleaned stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    cleaned = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return cleaned.length > 0 ? cleaned : @"unknown";
}

// YTMusic 9.39 renamed -[YTPlayerViewController playerResponse] to
// -contentPlayerResponse. Probing a short list of candidates and taking the first
// real YTPlayerResponse keeps this working across that rename (and across builds
// that still expose the old name) instead of hard-coding a single selector.
static NSArray<NSString *> *YTMUPlayerResponseKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[@"contentPlayerResponse", @"playerResponse", @"currentPlayerResponse"];
    });
    return keys;
}

static id YTMUSafeValue(id object, NSString *key) {
    if (!object || !key) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

%hook ELMTouchCommandPropertiesHandler
- (void)handleTap {

    if (class_getInstanceVariable([self class], "_controller") == NULL) {
        return %orig;
    }

    if (class_getInstanceVariable([self class], "_tapRecognizer") == NULL) {
        return %orig;
    }

    ELMNodeController *node = YTMUSafeValue(self, @"_controller");
    UIGestureRecognizer *tapRecognizer = YTMUSafeValue(self, @"_tapRecognizer");

    // The ELM bundle ships the badge node as a *template*: its key is stored as
    // "music_download_badge_$0" and the "$0" is substituted with the instance
    // index at load time. Older builds baked in the literal "music_download_badge_1",
    // so an exact compare now misses every time and the sheet never opens. Match on
    // the stable prefix instead and ignore whatever the template expanded to.
    NSString *nodeKey = YTMUSafeValue(node, @"key");
    if (![nodeKey isKindOfClass:[NSString class]] || ![nodeKey hasPrefix:@"music_download_badge"]) {
        return %orig;
    }

    UIViewController *ancestor = tapRecognizer.view._viewControllerForAncestor;
    if (![ancestor isKindOfClass:%c(YTMNowPlayingViewController)]) {
        return %orig;
    }

    YTMNowPlayingViewController *playingVC = (YTMNowPlayingViewController *)ancestor;
    YTMWatchViewController *watchVC = (YTMWatchViewController *)playingVC.parentViewController;
    YTPlayerViewController *playerVC = YTMUSafeValue(watchVC, @"playerViewController");
    YTPlayerResponse *playerResponse = [self resolvePlayerResponseFrom:playerVC];

    if (playerResponse) {
        YTMActionSheetController *sheetController = [%c(YTMActionSheetController) musicActionSheetController];
        sheetController.sourceView = tapRecognizer.view;
        [sheetController addHeaderWithTitle:LOC(@"SELECT_ACTION") subtitle:nil];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_AUDIO") iconImage:[%c(YTUIResources) audioOutline] style:0 handler:^ {
            [self downloadAudio:playerVC];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_COVER") iconImage:[%c(YTUIResources) outlineImageWithColor:[UIColor whiteColor]] style:0 handler:^ {
            [self downloadCoverImage:playerVC];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_PREMIUM") iconImage:[%c(YTUIResources) downloadOutline] secondaryIconImage:[%c(YTUIResources) youtubePremiumBadgeLight] accessibilityIdentifier:nil handler:^ {
            return %orig;
        }]];

        if (YTMU(@"downloadAudio") && YTMU(@"downloadCoverImage")) {
            [sheetController presentFromViewController:playingVC animated:YES completion:nil];
        } else if (YTMU(@"downloadAudio")) {
            [self downloadAudio:playerVC];
        } else if (YTMU(@"downloadCoverImage")) {
            [self downloadCoverImage:playerVC];
        }
    } else {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"DONT_RUSH");
        alertView.subtitle = LOC(@"DONT_RUSH_DESC");
        [alertView show];
    }
}

// Walk a small, fixed set of candidate selectors to obtain the player response.
// If the direct view-controller chain comes back empty (player not attached yet,
// or a differently-named controller), try to locate the response through the
// node's own context before giving up.
%new
- (YTPlayerResponse *)resolvePlayerResponseFrom:(id)object {
    if (!object) return nil;

    for (NSString *key in YTMUPlayerResponseKeys()) {
        id candidate = YTMUSafeValue(object, key);
        if ([candidate isKindOfClass:%c(YTPlayerResponse)]) {
            return candidate;
        }
    }

    for (id candidate in @[YTMUSafeValue(object, @"_controller"),
                           YTMUSafeValue(object, @"controller"),
                           YTMUSafeValue(object, @"parentViewController"),
                           YTMUSafeValue(object, @"presentingViewController")]) {
        for (NSString *key in YTMUPlayerResponseKeys()) {
            id response = YTMUSafeValue(candidate, key);
            if ([response isKindOfClass:%c(YTPlayerResponse)]) {
                return response;
            }
        }
    }

    return nil;
}

%new
- (void)downloadAudio:(YTPlayerViewController *)playerVC {
    YTPlayerResponse *playerResponse = [self resolvePlayerResponseFrom:playerVC];

    NSString *title = [YTMUSafeValue(YTMUSafeValue(YTMUSafeValue(playerResponse, @"playerData"), @"videoDetails"), @"title") stringByReplacingOccurrencesOfString:@"/" withString:@""];
    NSString *author = [YTMUSafeValue(YTMUSafeValue(YTMUSafeValue(playerResponse, @"playerData"), @"videoDetails"), @"author") stringByReplacingOccurrencesOfString:@"/" withString:@""];
    NSString *urlStr = YTMUSafeValue(YTMUSafeValue(YTMUSafeValue(playerResponse, @"playerData"), @"streamingData"), @"hlsManifestURL");

    if (urlStr.length == 0) {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"OOPS");
        alertView.subtitle = LOC(@"LINK_NOT_FOUND");
        [alertView show];
        return;
    }

    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    ffmpeg.tempName = YTMUSafeValue(playerVC, @"contentVideoID");
    ffmpeg.mediaName = [NSString stringWithFormat:@"%@ - %@", author, title];
    ffmpeg.duration = round([YTMUSafeValue(playerVC, @"currentVideoTotalMediaTime") doubleValue]);

    NSURL *manifestURL = [NSURL URLWithString:urlStr];
    if (!manifestURL) {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"OOPS");
        alertView.subtitle = LOC(@"LINK_NOT_FOUND");
        [alertView show];
        return;
    }

    // Fetch the manifest off the main thread. Doing this synchronously was the
    // other half of the hang: a slow manifest request blocked the UI thread and
    // the ffmpeg transcode never even started.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *extractedURL = [self getURLFromManifest:manifestURL];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (extractedURL.length == 0) {
                YTAlertView *alertView = [%c(YTAlertView) infoDialog];
                alertView.title = LOC(@"OOPS");
                alertView.subtitle = LOC(@"LINK_NOT_FOUND");
                [alertView show];
                return;
            }

            [ffmpeg downloadAudio:extractedURL];

            // Fetch the cover art alongside the transcode rather than before it.
            YTIThumbnailDetails *thumbnailDetails = YTMUSafeValue(YTMUSafeValue(YTMUSafeValue(playerResponse, @"playerData"), @"videoDetails"), @"thumbnail");
            NSArray *thumbnailsArray = YTMUSafeValue(thumbnailDetails, @"thumbnailsArray");
            YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
            NSString *thumbnailURL = YTMUSafeValue(thumbnail, @"URL");

            if (thumbnailURL.length == 0) return;

            [self fetchCoverDataFromURL:[NSURL URLWithString:thumbnailURL]
                                fileName:[NSString stringWithFormat:@"%@ - %@", author, title]];
        });
    });
}

%new
- (void)fetchCoverDataFromURL:(NSURL *)url fileName:(NSString *)fileName {
    NSString *safeName = [YTMUSanitizeFileName(fileName) stringByAppendingPathExtension:@"png"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __block NSData *imageData = nil;
        __block BOOL finished = NO;

        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        NSURLSessionDataTask *task = [YTMUSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
            if (!error && http.statusCode >= 200 && http.statusCode < 300 && data.length > 0 && data.length <= YTMUMaxImageBytes) {
                imageData = data;
            }
            finished = YES;
            dispatch_semaphore_signal(done);
        }];
        [task resume];

        // NSURLSession's own timeouts should fire first; this is only a backstop
        // so a wedged task can never pin this thread forever.
        dispatch_time_t limit = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((YTMUResourceTimeout + 5.0) * NSEC_PER_SEC));
        if (dispatch_semaphore_wait(done, limit) != 0 || !finished || imageData == nil) {
            [task cancel];
            return;
        }

        NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
        NSURL *folderURL = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];
        // Make sure the destination exists: the cover fetch races the transcode, so
        // it can win and write into a folder that does not exist yet.
        [[NSFileManager defaultManager] createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];

        NSURL *coverURL = [folderURL URLByAppendingPathComponent:safeName];
        [imageData writeToURL:coverURL atomically:YES];
    });
}

%new
- (void)downloadCoverImage:(YTPlayerViewController *)playerVC {
    YTPlayerResponse *playerResponse = [self resolvePlayerResponseFrom:playerVC];

    NSMutableArray *thumbnailsArray = YTMUSafeValue(YTMUSafeValue(YTMUSafeValue(playerResponse, @"playerData"), @"videoDetails"), @"thumbnailsArray");
    YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
    NSString *thumbnailURLString = YTMUSafeValue(thumbnail, @"URL");
    NSUInteger thumbnailWidth = [YTMUSafeValue(thumbnail, @"width") unsignedIntegerValue];

    if (thumbnailURLString.length == 0) {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"OOPS");
        alertView.subtitle = LOC(@"LINK_NOT_FOUND");
        [alertView show];
        return;
    }

    // The original code compared thumbnail.width against thumbnail.height, so it
    // built the wrong substitution key unless the art happened to be square and
    // never produced a larger image. Only rewrite when we actually know the width.
    NSString *thumbnailURL = thumbnailURLString;
    if (thumbnailWidth > 0) {
        NSString *sizeToken = [NSString stringWithFormat:@"w%lu-h%lu-", (unsigned long)thumbnailWidth, (unsigned long)thumbnailWidth];
        thumbnailURL = [thumbnailURL stringByReplacingOccurrencesOfString:sizeToken withString:@"w2048-h2048-"];
    }

    NSURL *link = [NSURL URLWithString:thumbnailURL];
    if (!link) {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"OOPS");
        alertView.subtitle = LOC(@"LINK_NOT_FOUND");
        [alertView show];
        return;
    }

    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    [ffmpeg downloadImage:link];
}

%new
- (NSString *)getURLFromManifest:(NSURL *)manifest {
    __block NSData *manifestData = nil;
    __block BOOL finished = NO;

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [YTMUSession() dataTaskWithURL:manifest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (!error && http.statusCode >= 200 && http.statusCode < 300 && data.length > 0 && data.length <= YTMUMaxManifestBytes) {
            manifestData = data;
        }
        finished = YES;
        dispatch_semaphore_signal(done);
    }];
    [task resume];

    dispatch_time_t limit = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((YTMURequestTimeout + 5.0) * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(done, limit) != 0 || !finished || manifestData == nil) {
        [task cancel];
        return nil;
    }

    NSString *manifestString = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
    if (manifestString.length == 0) {
        return nil;
    }

    NSArray *manifestLines = [manifestString componentsSeparatedByString:@"\n"];

    NSArray *groupIDS = @[@"234", @"233"]; // Our priority to find group id 234
    for (NSString *groupID in groupIDS) {
        for (NSString *line in manifestLines) {
            NSString *searchString = [NSString stringWithFormat:@"TYPE=AUDIO,GROUP-ID=\"%@\"", groupID];
            if ([line containsString:searchString]) {
                NSRange startRange = [line rangeOfString:@"https://"];
                NSRange endRange = [line rangeOfString:@"index.m3u8"];

                // Guard the subtraction: an "index.m3u8" appearing before "https://"
                // used to underflow NSMaxRange and produce a bogus slice.
                if (startRange.location == NSNotFound || endRange.location == NSNotFound || endRange.location < startRange.location) {
                    continue;
                }

                NSRange targetRange = NSMakeRange(startRange.location, NSMaxRange(endRange) - startRange.location);
                return [line substringWithRange:targetRange];
            }
        }
    }

    return nil;
}
%end