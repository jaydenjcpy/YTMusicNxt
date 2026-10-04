#import <UIKit/UIKit.h>
#import "../Headers/VendoredCredits.h"
#import "PremiumSettingsController.h"
#import "PlayerSettingsController.h"
#import "ThemeSettingsController.h"
#import "NavBarSettingsController.h"
#import "TabBarSettingsController.h"
#import "ABFlagsSettingsController.h"

@interface YTMUltimateSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource> 
@property (nonatomic, strong) UITableView* tableView;
@end
