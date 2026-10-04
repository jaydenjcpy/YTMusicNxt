#import "Headers/VendoredCredits.h"

@implementation YTMUVendoredCredit

+ (YTMUVendoredCredit *)creditWithName:(NSString *)name
                                author:(NSString *)author
                               license:(NSString *)license
                                   url:(NSString *)url
                               changes:(NSString *)changes {
    YTMUVendoredCredit *credit = [[YTMUVendoredCredit alloc] init];
    credit->_name = [name copy];
    credit->_author = [author copy];
    credit->_license = [license copy];
    credit->_url = [url copy];
    credit->_changes = [changes copy];
    return credit;
}

+ (NSArray<YTMUVendoredCredit *> *)allCredits {
    static NSArray *credits = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        credits = @[
            [self creditWithName:@"VolumeBoostYT"
                          author:@"vasirakcalgux"
                         license:@"MIT"
                             url:@"https://github.com/irum0320/VolumeBoostYT"
                         changes:@"YouTube-only settings injection replaced by a switch in YTMusicUltimate settings; defaults to off."],
            [self creditWithName:@"Return-YouTube-Music-Dislikes"
                          author:@"PoomSmart"
                         license:@"GPL-3.0"
                             url:@"https://github.com/PoomSmart/Return-YouTube-Music-Dislikes"
                         changes:@"Settings screen replaced by switches in YTMusicUltimate settings, defaults off, nil video IDs handled."],
        ];
    });

    return credits;
}

+ (NSArray<NSString *> *)footerLines {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    for (YTMUVendoredCredit *credit in [self allCredits]) {
        [lines addObject:[NSString stringWithFormat:@"%@ by %@ (%@)", credit.name, credit.author, credit.license]];
    }

    return lines;
}

@end