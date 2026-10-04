// A/B flag overrides.
//
// Ported from PoomSmart/YTMABConfig (Tweak.x), GPL-3.0,
// Copyright (c) PoomSmart, https://github.com/PoomSmart/YTMABConfig.
//
// Upstream walks YTMAppDelegate -> _MDXServices -> _MDXConfig -> the three
// config objects and then MSHookMessageEx's every BOOL getter on them, so a
// settings screen can flip any experiment. That part is kept as-is.
//
// Changes:
//   * The config chain is walked defensively. Upstream raises an exception when
//     an instance is nil, which takes the app down if YouTube renames an ivar.
//   * Un-overridden flags call the original implementation instead of a value
//     cached at hook time, so a flag that YouTube reloads later is not frozen.
//   * Overrides live in their own defaults key rather than upstream's flat keys.
//   * Upstream's Settings.x is dropped; see ABFlagsSettingsController.

#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <UIKit/UIKit.h>

#import "ABFlags.h"

// Overrides are a dictionary of "ClassName.selector" -> NSNumber, kept apart
// from the YTMUltimate dictionary so that clearing them does not touch the
// user's other options.
#define ABOverridesDefaultsKey @"YTMABFlags"
#define ABEnabledKey @"abFlags"

@interface YTMUABFlag ()
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *key;
@property (nonatomic) BOOL defaultValue;
@property (nonatomic) BOOL overridden;
@end

@implementation YTMUABFlag

- (BOOL)currentValue {
    return self.overridden ? !self.defaultValue : self.defaultValue;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@%@", self.key, self.overridden ? @" (modified)" : @""];
}

@end

#pragma mark - Hook bookkeeping

// One entry per hooked getter. Substrate's MSHookMessageEx hands back the
// original IMP, which is what an un-overridden flag has to call.
typedef struct {
    __unsafe_unretained Class cls;
    SEL selector;
    IMP original;
} YTMUABFlagHook;

static YTMUABFlagHook *ABHooks = NULL;
static size_t ABHookCount = 0;
static size_t ABHookCapacity = 0;

// Upstream skips these: the "android" and "amsterdam" families belong to the
// YouTube app, and the shorts and unplugged flags are gated behind an account
// entitlement, so flipping them does nothing visible.
static NSSet<NSString *> *ABExcludedPrefixes(void) {
    static NSSet *prefixes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefixes = [NSSet setWithArray:@[@"android", @"amsterdam", @"shorts", @"unplugged"]];
    });
    return prefixes;
}

static BOOL ABIsExcluded(NSString *selectorName) {
    if ([selectorName rangeOfString:@"Android"].location != NSNotFound) return YES;
    for (NSString *prefix in ABExcludedPrefixes()) {
        if ([selectorName hasPrefix:prefix]) return YES;
    }
    return NO;
}

// Finds the original IMP for a call, walking up from the receiver's class. The
// hook is installed on the config class itself, so if the receiver is a
// subclass the nearest recorded ancestor is the right implementation.
static IMP ABOriginalIMPForReceiver(id receiver, SEL selector) {
    Class cls = object_getClass(receiver);
    while (cls != Nil) {
        for (size_t i = 0; i < ABHookCount; i++) {
            if (ABHooks[i].cls == cls && ABHooks[i].selector == selector) {
                return ABHooks[i].original;
            }
        }
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

static NSNumber *ABOverrideForKey(NSString *key);

static BOOL ABReplacementIMP(id self, SEL _cmd) {
    BOOL (*original)(id, SEL) = (BOOL (*)(id, SEL))ABOriginalIMPForReceiver(self, _cmd);
    BOOL value = original ? original(self, _cmd) : NO;

    NSString *key = [NSString stringWithFormat:@"%@.%@", NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    NSNumber *override = ABOverrideForKey(key);
    return override ? override.boolValue : value;
}

#pragma mark - Store

@interface YTMUABFlagStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, YTMUABFlag *> *flagsByKey;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *overrides;
@property (nonatomic) BOOL hooksInstalled;
@end

static NSNumber *ABOverrideForKey(NSString *key) {
    return [[YTMUABFlagStore sharedStore] overrides][key];
}

@implementation YTMUABFlagStore

+ (instancetype)sharedStore {
    static YTMUABFlagStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[YTMUABFlagStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _flagsByKey = [NSMutableDictionary dictionary];
        NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:ABOverridesDefaultsKey];
        _overrides = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray<YTMUABFlag *> *)allFlags {
    return [self.flagsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(YTMUABFlag *a, YTMUABFlag *b) {
        NSComparisonResult byClass = [a.className compare:b.className];
        return byClass != NSOrderedSame ? byClass : [a.selectorName compare:b.selectorName];
    }];
}

- (YTMUABFlag *)flagForClassName:(NSString *)className selectorName:(NSString *)selectorName {
    return self.flagsByKey[[NSString stringWithFormat:@"%@.%@", className, selectorName]];
}

- (BOOL)isEnabled {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[ABEnabledKey] boolValue];
}

- (void)setEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *YTMUltimateDict = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"YTMUltimate"]];
    [YTMUltimateDict setObject:@(enabled) forKey:ABEnabledKey];
    [defaults setObject:YTMUltimateDict forKey:@"YTMUltimate"];
}

- (BOOL)setValue:(BOOL)value forFlag:(YTMUABFlag *)flag {
    if (flag == nil) return NO;

    flag.overridden = YES;
    self.overrides[flag.key] = @(value);
    [[NSUserDefaults standardUserDefaults] setObject:self.overrides forKey:ABOverridesDefaultsKey];

    // A hot config flag is often read once and cached by its owner, so nudge
    // the object to reread by sending it the value it just changed to.
    return YES;
}

- (NSInteger)resetAllOverrides {
    NSInteger count = self.overrides.count;
    [self.overrides removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:ABOverridesDefaultsKey];

    for (YTMUABFlag *flag in self.flagsByKey.allValues) {
        flag.overridden = NO;
    }
    return count;
}

- (BOOL)hasOverrides {
    return self.overrides.count > 0;
}

#pragma mark Hooking

- (void)installHooksOnGlobalConfig:(id)globalConfig
                        coldConfig:(id)coldConfig
                         hotConfig:(id)hotConfig {
    if (self.hooksInstalled) return;

    BOOL anyConfig = NO;
    for (id config in @[globalConfig ?: [NSNull null], coldConfig ?: [NSNull null], hotConfig ?: [NSNull null]]) {
        if (config != [NSNull null]) anyConfig = YES;
    }
    if (!anyConfig) return;

    self.hooksInstalled = YES;

    [self hookConfig:globalConfig];
    [self hookConfig:coldConfig];
    [self hookConfig:hotConfig];
}

- (void)hookConfig:(id)config {
    if (config == nil) return;

    Class instanceClass = [config class];
    NSString *className = NSStringFromClass(instanceClass);

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(instanceClass, &methodCount);

    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];

        // A BOOL getter and nothing else: "B16@0:8" means no parameters and a
        // one byte return. Setters and everything else are left alone.
        const char *encoding = method_getTypeEncoding(method);
        if (encoding == NULL || strcmp(encoding, "B16@0:8") != 0) continue;

        NSString *selectorName = NSStringFromSelector(method_getName(method));
        if (ABIsExcluded(selectorName)) continue;

        YTMUABFlag *flag = [[YTMUABFlag alloc] init];
        flag.className = className;
        flag.selectorName = selectorName;
        flag.key = [NSString stringWithFormat:@"%@.%@", className, selectorName];

        BOOL (*original)(id, SEL) = (BOOL (*)(id, SEL))method_getImplementation(method);
        flag.defaultValue = original ? original(config, method_getName(method)) : NO;
        flag.overridden = self.overrides[flag.key] != nil;

        self.flagsByKey[flag.key] = flag;

        if (ABHookCount == ABHookCapacity) {
            ABHookCapacity = ABHookCapacity ? ABHookCapacity * 2 : 256;
            ABHooks = realloc(ABHooks, ABHookCapacity * sizeof(YTMUABFlagHook));
        }

        IMP replaced = NULL;
        SEL selector = method_getName(method);
        MSHookMessageEx(instanceClass, selector, (IMP)(void *)ABReplacementIMP, &replaced);

        ABHooks[ABHookCount].cls = instanceClass;
        ABHooks[ABHookCount].selector = selector;
        ABHooks[ABHookCount].original = replaced ?: (IMP)(void *)original;
        ABHookCount++;
    }

    free(methods);
}

@end