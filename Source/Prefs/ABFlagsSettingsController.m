// A searchable browser for YouTube's A/B experiment flags.
//
// Replaces the settings screen from PoomSmart/YTMABConfig, which is built from
// YTMSettingsSectionItem's itemWithTitle:... and switchItemWithTitle:...
// factories. YouTube Music 9.39 dropped both (YTMSettingsSectionItem now only
// has initWithRenderer: and a delegate), so upstream's screen has nothing to
// render into. This walks the same flag list the hook discovered instead.
//
// What is not carried over: grouping by inferred category, import/export of
// flag sets, and the "view modified settings" and "copy current settings"
// actions. The list is sorted by class and selector, which is enough to find a
// flag by name.

#import "ABFlagsSettingsController.h"
#import "../Headers/Localization.h"
#import "../Headers/ABCSwitch.h"
#import "../ABFlags/ABFlags.h"

@interface ABFlagsSettingsController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<YTMUABFlag *> *visibleFlags;

@end

@implementation ABFlagsSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = LOC(@"AB_FLAGS");
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44.0;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = LOC(@"AB_FLAGS_SEARCH");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOC(@"AB_FLAGS_RESET")
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(resetTapped)];

    [self applyFilter:@""];
}

- (NSArray<YTMUABFlag *> *)flagsMatching:(NSString *)query {
    NSArray<YTMUABFlag *> *flags = [YTMUABFlagStore sharedStore].allFlags;
    if (query.length == 0) return flags;

    return [flags filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(YTMUABFlag *flag, NSDictionary *bindings) {
        return [flag.selectorName rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound
            || [flag.className rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
    }]];
}

- (void)applyFilter:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.visibleFlags = [self flagsMatching:trimmed];
    [self.tableView reloadData];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter:searchController.searchBar.text];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Section 0 is the master switch, section 1 the flags themselves.
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : self.visibleFlags.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    if (self.visibleFlags.count == 0) return LOC(@"AB_FLAGS_EMPTY");
    return [NSString stringWithFormat:LOC(@"AB_FLAGS_FOOTER"), (unsigned long)self.visibleFlags.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"flagCell"];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"flagCell"];
        }

        cell.textLabel.text = LOC(@"AB_FLAGS_ENABLED");
        cell.detailTextLabel.text = LOC(@"AB_FLAGS_ENABLED_DESC");
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

        ABCSwitch *toggle = [[NSClassFromString(@"ABCSwitch") alloc] init];
        toggle.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
        toggle.on = [YTMUABFlagStore sharedStore].isEnabled;
        [toggle addTarget:self action:@selector(enabledSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"flagCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"flagCell"];
    }

    YTMUABFlag *flag = self.visibleFlags[indexPath.row];
    cell.textLabel.text = flag.selectorName;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    // An overridden flag is the one thing worth spotting in a list this long.
    cell.textLabel.textColor = flag.overridden ? [UIColor systemOrangeColor] : [UIColor labelColor];
    cell.detailTextLabel.text = flag.className;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    ABCSwitch *toggle = [[NSClassFromString(@"ABCSwitch") alloc] init];
    toggle.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
    toggle.on = flag.currentValue;
    toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(flagSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Actions

- (void)enabledSwitchChanged:(UISwitch *)sender {
    YTMUABFlagStore *store = [YTMUABFlagStore sharedStore];
    [store setEnabled:sender.isOn];

    // The hooks are installed at launch, so turning this on mid-session cannot
    // hook anything. Say so rather than leaving switches that do nothing.
    if (sender.isOn && store.allFlags.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"AB_FLAGS_ENABLED")
                                                                       message:LOC(@"AB_FLAGS_RESTART")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOC(@"OK") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)flagSwitchChanged:(UISwitch *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:1];
    if (indexPath.row >= (NSInteger)self.visibleFlags.count) return;

    YTMUABFlag *flag = self.visibleFlags[indexPath.row];
    [[YTMUABFlagStore sharedStore] setValue:sender.isOn forFlag:flag];

    // Only the row's colour changes, so a full reload would drop the search
    // field's first responder and make the list jump.
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)resetTapped {
    YTMUABFlagStore *store = [YTMUABFlagStore sharedStore];
    if (!store.hasOverrides) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"AB_FLAGS_RESET")
                                                                   message:LOC(@"AB_FLAGS_RESET_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"AB_FLAGS_RESET") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [store resetAllOverrides];
        [self applyFilter:self.searchController.searchBar.text ?: @""];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end