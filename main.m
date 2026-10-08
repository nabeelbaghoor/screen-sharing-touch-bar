// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nabeel Hassan
// Screen Sharing Touch Bar
// Mirrors the Screen Sharing app's toolbar on the Touch Bar whenever Screen Sharing is the frontmost app.
// The item list and order come from Screen Sharing's saved toolbar configuration, so customizing the
// toolbar (View > Customize Toolbar) updates the Touch Bar too. Buttons press the matching menu item
// through the Accessibility API, and toggles light up blue when they are on, like the toolbar.

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>
#include <dlfcn.h>

// Private Touch Bar API (same calls used by MTMR, Pock and BetterTouchTool).
@interface NSTouchBarItem (SSTBPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (SSTBPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

typedef void (*DFRSetPresenceFn)(NSTouchBarItemIdentifier, BOOL);
typedef void (*DFRShowsCloseBoxFn)(BOOL);

static NSString *const kScreenSharingBundleID = @"com.apple.ScreenSharing";
static NSTouchBarItemIdentifier const kTrayID = @"com.nabeelbaghoor.sstb.tray";
static NSString *const kItemPrefix = @"sstb.";
static const CGFloat kBarBudget = 990;      // usable Touch Bar width in points
static const CGFloat kItemGap = 8;
static const CGFloat kIconOnlyWidth = 56;

// Screen Sharing's default toolbar, used until its saved configuration can be read.
static NSArray<NSString *> *DefaultToolbarIDs(void) {
    return @[@"ControlObserve", @"Dynamic", @"HDR", @"NSToolbarSpaceItem", @"Launchpad", @"MissionControl",
             @"Desktop", @"NSToolbarFlexibleSpaceItem", @"MultiDisplay", @"Zoom", @"ZoomToFit"];
}

// Known toolbar items: label, SF Symbol fallbacks, menu titles to press, and how to read their state.
//   check:   on when the menu item has a checkmark
//   onTitle: on when this one of the alternative titles is the one currently in the menu
static NSDictionary<NSString *, NSDictionary *> *KnownItems(void) {
    static NSDictionary *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = @{
            @"ControlObserve": @{@"label": @"Control", @"symbols": @[@"cursorarrow.rays", @"cursorarrow"],
                                 @"titles": @[@"Switch to Observe Mode", @"Switch to Control Mode"],
                                 @"onTitle": @"Switch to Observe Mode"},
            @"Dynamic":        @{@"label": @"Dynamic", @"symbols": @[@"arrow.up.left.and.arrow.down.right"],
                                 @"titles": @[@"Dynamic Resolution"], @"check": @YES},
            @"HDR":            @{@"label": @"HDR", @"symbols": @[@"square.3.layers.3d", @"square.stack.3d.up"],
                                 @"titles": @[@"High Dynamic Range"], @"check": @YES},
            @"Launchpad":      @{@"label": @"Launchpad", @"symbols": @[@"square.grid.3x2"], @"titles": @[@"Launchpad"]},
            @"MissionControl": @{@"label": @"Mission Control", @"symbols": @[@"rectangle.3.group", @"rectangle.split.3x1"],
                                 @"titles": @[@"Mission Control"]},
            @"Desktop":        @{@"label": @"Desktop", @"symbols": @[@"menubar.dock.rectangle", @"desktopcomputer"],
                                 @"titles": @[@"Desktop"]},
            @"AppExposé":      @{@"label": @"App Windows", @"symbols": @[@"macwindow.on.rectangle", @"rectangle.stack"],
                                 @"titles": @[@"App Windows", @"App Exposé"]},
            @"MultiDisplay":   @{@"label": @"Displays", @"symbols": @[@"display.2"],
                                 @"titles": @[@"Show All Displays", @"Switch Displays", @"Next Display", @"Displays"]},
            @"ZoomToFit":      @{@"label": @"Scale to Fit", @"symbols": @[@"arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", @"aspectratio"],
                                 @"titles": @[@"Turn Scaling Off", @"Turn Scaling On"], @"onTitle": @"Turn Scaling Off"},
        };
    });
    return items;
}

static NSImage *SymbolImage(NSArray<NSString *> *names, NSString *desc) {
    for (NSString *n in names) {
        NSImage *img = [NSImage imageWithSystemSymbolName:n accessibilityDescription:desc];
        if (img) return img;
    }
    return [NSImage imageWithSystemSymbolName:@"square.dashed" accessibilityDescription:desc];
}

// "MultiDisplay" -> "Multi Display" for toolbar items this app doesn't know yet.
static NSString *PrettyLabel(NSString *toolbarID) {
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < toolbarID.length; i++) {
        unichar c = [toolbarID characterAtIndex:i];
        if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) [s appendString:@" "];
        [s appendFormat:@"%C", c];
    }
    return s;
}

static NSDictionary *SpecFor(NSString *toolbarID) {
    NSDictionary *known = KnownItems()[toolbarID];
    if (known) return known;
    NSString *label = PrettyLabel(toolbarID);
    return @{@"label": label, @"symbols": @[@"questionmark.square.dashed"], @"titles": @[label]};
}

#pragma mark - Accessibility helpers

static NSString *AXTitle(AXUIElementRef el) {
    CFTypeRef v = NULL;
    if (AXUIElementCopyAttributeValue(el, kAXTitleAttribute, &v) != kAXErrorSuccess || !v) return nil;
    id obj = (__bridge_transfer id)v;
    return [obj isKindOfClass:[NSString class]] ? obj : nil;
}

static NSArray *AXChildren(AXUIElementRef el) {
    CFTypeRef v = NULL;
    if (AXUIElementCopyAttributeValue(el, kAXChildrenAttribute, &v) != kAXErrorSuccess || !v) return @[];
    return (__bridge_transfer NSArray *)v;
}

static BOOL AXBool(AXUIElementRef el, CFStringRef attr, BOOL fallback) {
    CFTypeRef v = NULL;
    if (AXUIElementCopyAttributeValue(el, attr, &v) != kAXErrorSuccess || !v) return fallback;
    BOOL b = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : fallback;
    CFRelease(v);
    return b;
}

static BOOL AXChecked(AXUIElementRef el) {
    CFTypeRef v = NULL;
    if (AXUIElementCopyAttributeValue(el, kAXMenuItemMarkCharAttribute, &v) != kAXErrorSuccess || !v) return NO;
    id obj = (__bridge_transfer id)v;
    return [obj isKindOfClass:[NSString class]] && [obj length] > 0;
}

// Collects every top-level menu item of the app (title -> element), skipping the Apple menu.
static NSDictionary<NSString *, id> *MenuItems(pid_t pid) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFTypeRef bar = NULL;
    if (AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute, &bar) == kAXErrorSuccess && bar) {
        NSArray *barItems = AXChildren((AXUIElementRef)bar);
        for (NSUInteger i = 1; i < barItems.count; i++) {
            for (id menu in AXChildren((__bridge AXUIElementRef)barItems[i])) {
                for (id item in AXChildren((__bridge AXUIElementRef)menu)) {
                    NSString *t = AXTitle((__bridge AXUIElementRef)item);
                    if (t.length && !out[t]) out[t] = item;
                }
            }
        }
        CFRelease(bar);
    }
    CFRelease(app);
    return out;
}

static id FirstMenuItem(NSDictionary *menu, NSArray<NSString *> *titles, NSString **matched) {
    for (NSString *t in titles) {
        if (menu[t]) { if (matched) *matched = t; return menu[t]; }
    }
    return nil;
}

#pragma mark - App

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTouchBarDelegate, NSMenuDelegate>
@property (strong) NSTouchBar *bar;
@property (strong) NSCustomTouchBarItem *trayItem;
@property (strong) NSArray<NSString *> *toolbarIDs;
@property (strong) NSSet<NSString *> *iconOnly;
@property (strong) NSMutableDictionary<NSString *, NSControl *> *controls;
@property (strong) NSStatusItem *statusItem;
@property (strong) NSTimer *stateTimer;
@property (strong) NSTimer *configTimer;
@property (assign) BOOL shown;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:kTrayID];
    self.trayItem.view = [NSButton buttonWithImage:SymbolImage(@[@"display.2"], @"Screen Sharing") target:nil action:nil];
    [NSTouchBarItem addSystemTrayItem:self.trayItem];
    void *dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
    DFRSetPresenceFn setPresence = dfr ? (DFRSetPresenceFn)dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier") : NULL;
    if (setPresence) setPresence(kTrayID, NO);
    DFRShowsCloseBoxFn showsCloseBox = dfr ? (DFRShowsCloseBoxFn)dlsym(dfr, "DFRSystemModalShowsCloseBoxWhenFrontMost") : NULL;
    if (showsCloseBox) showsCloseBox(NO);

    [self rebuildBarWithToolbarIDs:DefaultToolbarIDs()];
    [self reloadToolbarConfig];
    [self setupStatusItem];

    NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(frontAppChanged:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];
    [self updateForFrontApp:[NSWorkspace sharedWorkspace].frontmostApplication];
}

#pragma mark Toolbar configuration

// Reads Screen Sharing's saved toolbar (it lives in its sandbox container; `defaults` resolves that).
- (void)reloadToolbarConfig {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/defaults"];
        task.arguments = @[@"export", kScreenSharingBundleID, @"-"];
        NSPipe *outPipe = [NSPipe pipe];
        task.standardOutput = outPipe;
        task.standardError = [NSFileHandle fileHandleWithNullDevice];
        if (![task launchAndReturnError:nil]) return;
        NSData *data = [outPipe.fileHandleForReading readDataToEndOfFile];
        [task waitUntilExit];
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
        NSArray *best = nil;
        for (NSString *key in plist) {
            if (![key hasPrefix:@"NSToolbar Configuration"]) continue;
            NSArray *ids = plist[key][@"TB Item Identifiers"];
            if (![ids isKindOfClass:[NSArray class]]) continue;
            if (!best || [ids containsObject:@"ControlObserve"]) best = ids;
        }
        if (!best.count) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![best isEqualToArray:self.toolbarIDs]) [self rebuildBarWithToolbarIDs:best];
        });
    });
}

- (NSString *)touchBarIDForToolbarID:(NSString *)tid index:(NSUInteger)i {
    if ([tid isEqualToString:@"NSToolbarSpaceItem"]) return NSTouchBarItemIdentifierFixedSpaceLarge;
    if ([tid isEqualToString:@"NSToolbarFlexibleSpaceItem"]) return NSTouchBarItemIdentifierFlexibleSpace;
    if ([tid isEqualToString:@"NSToolbarSeparatorItem"]) return NSTouchBarItemIdentifierFixedSpaceSmall;
    if ([tid hasPrefix:@"NSToolbar"]) return nil;   // print, customize, sidebar and other system items
    return [NSString stringWithFormat:@"%@%@", kItemPrefix, tid];
}

- (CGFloat)labeledWidthForToolbarID:(NSString *)tid {
    if ([tid isEqualToString:@"Zoom"]) return 2 * kIconOnlyWidth;
    NSDictionary *spec = SpecFor(tid);
    NSButton *b = [NSButton buttonWithTitle:spec[@"label"] image:SymbolImage(spec[@"symbols"], spec[@"label"]) target:nil action:nil];
    b.imagePosition = NSImageLeading;
    return MAX(b.fittingSize.width + 16, 72);
}

// Keeps labels where they fit; drops labels from the widest buttons first when the bar is full.
- (NSSet *)iconOnlySetForToolbarIDs:(NSArray<NSString *> *)ids {
    NSMutableDictionary<NSString *, NSNumber *> *labeled = [NSMutableDictionary dictionary];
    CGFloat total = 0;
    for (NSString *tid in ids) {
        if ([tid isEqualToString:@"NSToolbarSpaceItem"]) { total += 32; continue; }
        if ([tid hasPrefix:@"NSToolbar"]) continue;
        CGFloat w = [self labeledWidthForToolbarID:tid];
        if (![tid isEqualToString:@"Zoom"]) labeled[tid] = @(w);
        total += w + kItemGap;
    }
    NSMutableSet *iconOnly = [NSMutableSet set];
    NSArray *byWidth = [labeled keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
    for (NSString *tid in byWidth) {
        if (total <= kBarBudget) break;
        total -= labeled[tid].doubleValue - kIconOnlyWidth;
        [iconOnly addObject:tid];
    }
    return iconOnly;
}

- (void)rebuildBarWithToolbarIDs:(NSArray<NSString *> *)ids {
    self.toolbarIDs = ids;
    self.iconOnly = [self iconOnlySetForToolbarIDs:ids];
    self.controls = [NSMutableDictionary dictionary];
    NSMutableArray *barIDs = [NSMutableArray array];
    [ids enumerateObjectsUsingBlock:^(NSString *tid, NSUInteger i, BOOL *stop) {
        NSString *bid = [self touchBarIDForToolbarID:tid index:i];
        if (bid) [barIDs addObject:bid];
    }];
    NSTouchBar *bar = [[NSTouchBar alloc] init];
    bar.delegate = self;
    bar.defaultItemIdentifiers = barIDs;
    BOOL wasShown = self.shown;
    if (wasShown) [NSTouchBar dismissSystemModalTouchBar:self.bar];
    self.bar = bar;
    if (wasShown) {
        [NSTouchBar presentSystemModalTouchBar:self.bar placement:1 systemTrayItemIdentifier:kTrayID];
        [self refreshStates];
    }
}

#pragma mark Status item

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = SymbolImage(@[@"rectangle.and.hand.point.up.left", @"display.2"], @"Screen Sharing Touch Bar");
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    self.statusItem.menu = menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"";
    NSMenuItem *title = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Screen Sharing Touch Bar %@", version] action:nil keyEquivalent:@""];
    title.enabled = NO;
    [menu addItem:title];
    BOOL trusted = AXIsProcessTrusted();
    NSMenuItem *ax = [[NSMenuItem alloc] initWithTitle:(trusted ? @"Accessibility: allowed" : @"Accessibility: not allowed (click to fix)")
                                                action:(trusted ? nil : @selector(openAccessibilitySettings:)) keyEquivalent:@""];
    ax.target = self;
    [menu addItem:ax];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"Open at Login" action:@selector(toggleLogin:) keyEquivalent:@""];
    login.target = self;
    if (@available(macOS 13.0, *)) {
        login.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
    } else {
        login.enabled = NO;
    }
    [menu addItem:login];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
}

- (void)openAccessibilitySettings:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (void)toggleLogin:(id)sender {
    if (@available(macOS 13.0, *)) {
        NSError *err = nil;
        if (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) [SMAppService.mainAppService unregisterAndReturnError:&err];
        else [SMAppService.mainAppService registerAndReturnError:&err];
        if (err) NSLog(@"Open at Login change failed: %@", err);
    }
}

- (void)quit:(id)sender {
    [self dismissBar];
    [NSApp terminate:nil];
}

#pragma mark Front app tracking

- (void)frontAppChanged:(NSNotification *)note {
    [self updateForFrontApp:note.userInfo[NSWorkspaceApplicationKey]];
}

- (void)updateForFrontApp:(NSRunningApplication *)app {
    if ([app.bundleIdentifier isEqualToString:kScreenSharingBundleID]) [self presentBar];
    else [self dismissBar];
}

- (void)presentBar {
    if (!self.shown) {
        [NSTouchBar presentSystemModalTouchBar:self.bar placement:1 systemTrayItemIdentifier:kTrayID];
        self.shown = YES;
        self.stateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshStates) userInfo:nil repeats:YES];
        self.configTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(reloadToolbarConfig) userInfo:nil repeats:YES];
    }
    [self reloadToolbarConfig];
    [self refreshStates];
}

- (void)dismissBar {
    if (!self.shown) return;
    [NSTouchBar dismissSystemModalTouchBar:self.bar];
    self.shown = NO;
    [self.stateTimer invalidate];
    [self.configTimer invalidate];
    self.stateTimer = nil;
    self.configTimer = nil;
}

#pragma mark Touch Bar items

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    if (![identifier hasPrefix:kItemPrefix]) return nil;
    NSString *tid = [identifier substringFromIndex:kItemPrefix.length];
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];

    if ([tid isEqualToString:@"Zoom"]) {
        NSArray *images = @[SymbolImage(@[@"minus.magnifyingglass"], @"Zoom Out"), SymbolImage(@[@"plus.magnifyingglass"], @"Zoom In")];
        NSSegmentedControl *seg = [NSSegmentedControl segmentedControlWithImages:images
                                                                    trackingMode:NSSegmentSwitchTrackingMomentary
                                                                          target:self action:@selector(zoomTapped:)];
        [seg setWidth:kIconOnlyWidth - 6 forSegment:0];
        [seg setWidth:kIconOnlyWidth - 6 forSegment:1];
        self.controls[tid] = seg;
        item.view = seg;
        return item;
    }

    NSDictionary *spec = SpecFor(tid);
    NSImage *img = SymbolImage(spec[@"symbols"], spec[@"label"]);
    NSButton *b;
    if ([self.iconOnly containsObject:tid]) {
        b = [NSButton buttonWithImage:img target:self action:@selector(buttonTapped:)];
        [b.widthAnchor constraintEqualToConstant:kIconOnlyWidth].active = YES;
    } else {
        b = [NSButton buttonWithTitle:spec[@"label"] image:img target:self action:@selector(buttonTapped:)];
        b.imagePosition = NSImageLeading;
    }
    b.identifier = tid;
    self.controls[tid] = b;
    item.view = b;
    item.customizationLabel = spec[@"label"];
    return item;
}

- (pid_t)screenSharingPID {
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:kScreenSharingBundleID];
    return apps.count ? ((NSRunningApplication *)apps.firstObject).processIdentifier : 0;
}

- (void)pressMenuTitles:(NSArray<NSString *> *)titles {
    pid_t pid = [self screenSharingPID];
    if (!pid) return;
    if (!AXIsProcessTrusted()) { [self openAccessibilitySettings:nil]; return; }
    id item = FirstMenuItem(MenuItems(pid), titles, NULL);
    if (item) AXUIElementPerformAction((__bridge AXUIElementRef)item, kAXPressAction);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshStates];
    });
}

- (void)buttonTapped:(NSButton *)sender {
    [self pressMenuTitles:SpecFor(sender.identifier)[@"titles"]];
}

- (void)zoomTapped:(NSSegmentedControl *)sender {
    [self pressMenuTitles:@[sender.selectedSegment == 0 ? @"Zoom Out" : @"Zoom In"]];
}

// Mirror the toolbar: blue when a mode is on, dimmed when Screen Sharing has the command unavailable.
- (void)refreshStates {
    pid_t pid = [self screenSharingPID];
    if (!pid || !AXIsProcessTrusted()) return;
    NSDictionary *menu = MenuItems(pid);
    [self.controls enumerateKeysAndObjectsUsingBlock:^(NSString *tid, NSControl *control, BOOL *stop) {
        if ([tid isEqualToString:@"Zoom"]) {
            NSSegmentedControl *seg = (NSSegmentedControl *)control;
            id zOut = menu[@"Zoom Out"], zIn = menu[@"Zoom In"];
            [seg setEnabled:(zOut && AXBool((__bridge AXUIElementRef)zOut, kAXEnabledAttribute, YES)) forSegment:0];
            [seg setEnabled:(zIn && AXBool((__bridge AXUIElementRef)zIn, kAXEnabledAttribute, YES)) forSegment:1];
            return;
        }
        NSButton *b = (NSButton *)control;
        NSDictionary *spec = SpecFor(tid);
        NSString *matched = nil;
        id item = FirstMenuItem(menu, spec[@"titles"], &matched);
        if (!item) { b.enabled = NO; b.bezelColor = nil; return; }
        AXUIElementRef el = (__bridge AXUIElementRef)item;
        b.enabled = AXBool(el, kAXEnabledAttribute, YES);
        BOOL on = NO;
        if (spec[@"onTitle"]) on = [matched isEqualToString:spec[@"onTitle"]];
        else if ([spec[@"check"] boolValue]) on = AXChecked(el);
        b.bezelColor = on ? [NSColor systemBlueColor] : nil;
    }];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
