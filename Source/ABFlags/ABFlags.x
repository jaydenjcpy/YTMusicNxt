// A/B flag overrides, ported from PoomSmart/YTMABConfig (Tweak.x).
// GPL-3.0, Copyright (c) PoomSmart, https://github.com/PoomSmart/YTMABConfig
//
// See Source/ABFlags/ABFlags.m for what was kept and what changed.

#import <UIKit/UIKit.h>

#import "../Headers/YTMAppDelegate.h"
#import "ABFlags.h"

%hook YTMAppDelegate

- (void)createApplication:(id)application {
    %orig;
    if (![[YTMUABFlagStore sharedStore] isEnabled]) return;

    // The chain is YouTube's own: app delegate -> the media hub services ->
    // the settings object -> the three config objects holding the flags.
    // Upstream unwraps it with valueForKey: and raises if any link is missing;
    // here a missing link just means no flags to show.
    id mdxServices = nil;
    @try {
        mdxServices = [self valueForKey:@"_MDXServices"];
    } @catch (id exception) {
        return;
    }
    if (mdxServices == nil) return;

    id settings = nil;
    @try {
        settings = [mdxServices valueForKey:@"_MDXConfig"];
    } @catch (id exception) {
        return;
    }
    if (settings == nil) return;

    id globalConfig = nil, coldConfig = nil, hotConfig = nil;
    @try {
        globalConfig = [settings valueForKey:@"_globalConfig"];
        coldConfig = [settings valueForKey:@"_coldConfig"];
        hotConfig = [settings valueForKey:@"_hotConfig"];
    } @catch (id exception) {
        return;
    }

    if (globalConfig == nil && coldConfig == nil && hotConfig == nil) return;

    [[YTMUABFlagStore sharedStore] installHooksOnGlobalConfig:globalConfig
                                                   coldConfig:coldConfig
                                                    hotConfig:hotConfig];
}

%end