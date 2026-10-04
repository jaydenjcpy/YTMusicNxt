// A/B flag overrides, ported from PoomSmart/YTMABConfig.
//
// The three YouTube config objects expose thousands of BOOL getters that decide
// which experiments the app runs. Overriding them lets you turn features on
// before Google rolls them out to your account, or off when they misbehave.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTMUABFlag : NSObject

@property (nonatomic, copy, readonly) NSString *className;
@property (nonatomic, copy, readonly) NSString *selectorName;
// "YTGlobalConfig.enableFoo", the key overrides are stored under.
@property (nonatomic, copy, readonly) NSString *key;
// The value the app returned before we touched it.
@property (nonatomic, readonly) BOOL defaultValue;
// Whether the user has overridden this flag.
@property (nonatomic, readonly) BOOL overridden;
// The value in effect right now.
@property (nonatomic, readonly) BOOL currentValue;

@end

@interface YTMUABFlagStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, readonly) NSArray<YTMUABFlag *> *allFlags;

- (nullable YTMUABFlag *)flagForClassName:(NSString *)className selectorName:(NSString *)selectorName;

// Registers the config instances and hooks every BOOL getter on them. Safe to
// call more than once; later calls are ignored.
- (void)installHooksOnGlobalConfig:(nullable id)globalConfig
                        coldConfig:(nullable id)coldConfig
                         hotConfig:(nullable id)hotConfig;

- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)enabled;

// Sets one flag and persists it. Returns NO if the flag is unknown.
- (BOOL)setValue:(BOOL)value forFlag:(YTMUABFlag *)flag;

// Drops every override the user made.
- (NSInteger)resetAllOverrides;

// YES when at least one flag differs from its default.
- (BOOL)hasOverrides;

@end

NS_ASSUME_NONNULL_END