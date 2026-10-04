#import <UIKit/UIKit.h>

// Browser for YouTube's A/B experiment flags, replacing the settings screen
// PoomSmart/YTMABConfig builds with YTMSettingsSectionItem factories that
// YouTube Music 9.39 no longer has.
@interface ABFlagsSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>

@end