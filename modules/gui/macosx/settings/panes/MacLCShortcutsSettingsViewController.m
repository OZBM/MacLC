/*****************************************************************************
 * MacLCShortcutsSettingsViewController.m: Shortcuts Settings Pane for MacLC
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Settings Team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "settings/panes/MacLCShortcutsSettingsViewController.h"
#import "settings/MacLCConfigSafe.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>
#import <vlc_plugin.h>
#import <vlc_modules.h>

@interface MacLCShortcutsSettingsViewController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Hotkey data
@property (nonatomic, strong) NSMutableArray<NSString *> *allDescriptions;
@property (nonatomic, strong) NSMutableArray<NSString *> *allNames;
@property (nonatomic, strong) NSMutableArray<NSString *> *allCurrentShortcuts;
@property (nonatomic, strong) NSMutableArray<NSString *> *allDefaultShortcuts;

// Filtered indices for search
@property (nonatomic, strong) NSMutableArray<NSNumber *> *filteredIndices;

// Views
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSButton *changeButton;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) MacLCSettingsRow *mediaKeysRow;

// Key change sheet
@property (nonatomic, strong) NSWindow *keyChangeSheet;
@property (nonatomic, strong) NSTextField *sheetActionLabel;
@property (nonatomic, strong) NSTextField *sheetShortcutLabel;
@property (nonatomic, strong) NSTextField *sheetConflictLabel;
@property (nonatomic, strong) NSButton *sheetOkButton;
@property (nonatomic, copy, nullable) NSString *capturedKey;
@property (nonatomic, strong, nullable) id eventMonitor;
@property (nonatomic, assign) NSInteger editingIndex;

@end

@implementation MacLCShortcutsSettingsViewController

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _p_intf = intf;
        _allDescriptions = [NSMutableArray array];
        _allNames = [NSMutableArray array];
        _allCurrentShortcuts = [NSMutableArray array];
        _allDefaultShortcuts = [NSMutableArray array];
        _filteredIndices = [NSMutableArray array];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    return self;
}

#pragma mark - MacLCSettingsPane Protocol Properties

- (NSString *)paneTitle
{
    return _NS("Shortcuts");
}

- (NSString *)paneSymbolName
{
    return @"command";
}

- (NSString *)paneIdentifier
{
    return @"shortcuts";
}

- (NSArray<NSString *> *)searchKeywords
{
    NSMutableArray *keywords = [@[
        @"shortcuts", @"hotkeys", @"keyboard", @"key", @"binding",
        @"media keys", @"play", @"pause", @"stop", @"volume", @"fullscreen",
        @"macosx-mediakeys"
    ] mutableCopy];

    for (NSString *name in _allNames) {
        [keywords addObject:name.lowercaseString];
    }
    return keywords;
}

#pragma mark - View Lifecycle & Layout

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 950)];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    self.view = container;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.alignment = NSLayoutAttributeLeading;
    rootStack.spacing = [MacLCDesign groupSpacing];

    [container addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                                constant:[MacLCDesign windowContentMargin]],
        [rootStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                                 constant:-[MacLCDesign windowContentMargin]],
        [rootStack.topAnchor constraintEqualToAnchor:container.topAnchor
                                            constant:[MacLCDesign windowContentMargin]],
        [rootStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                               constant:-[MacLCDesign windowContentMargin]],
        [container.widthAnchor constraintGreaterThanOrEqualToConstant:480]
    ]];

    __weak typeof(self) weakSelf = self;

    // Card 1: Media Keys Options
    MacLCCardView *hardwareCard = [MacLCCardView cardViewWithTitle:_NS("Keyboard Integration")];
    hardwareCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:hardwareCard];
    [hardwareCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _mediaKeysRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Control with Mac Media Keys")
                                               explanation:_NS("Respond to keyboard Play/Pause, Fast Forward, and Rewind media keys.")
                                                     state:YES
                                                    action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _mediaKeysRow.defaultHint = _NS("Default: On");
    [hardwareCard.contentStackView addArrangedSubview:_mediaKeysRow];

    // Card 2: Hotkeys Table
    MacLCCardView *tableCard = [MacLCCardView cardViewWithTitle:_NS("Keyboard Shortcuts")];
    tableCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:tableCard];
    [tableCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    // Search bar above table
    _searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholderString = _NS("Filter shortcuts…");
    _searchField.delegate = self;
    [tableCard.contentStackView addArrangedSubview:_searchField];
    [_searchField.trailingAnchor constraintEqualToAnchor:tableCard.contentStackView.trailingAnchor].active = YES;

    // Table view in scroll view
    NSScrollView *tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    tableScrollView.hasVerticalScroller = YES;
    tableScrollView.autohidesScrollers = YES;
    tableScrollView.borderType = NSBezelBorder;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(tableDoubleClicked:);
    _tableView.rowHeight = 28.0;
    _tableView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *actionCol = [[NSTableColumn alloc] initWithIdentifier:@"action"];
    actionCol.title = _NS("Action");
    actionCol.width = 300.0;
    actionCol.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [_tableView addTableColumn:actionCol];

    NSTableColumn *keyCol = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    keyCol.title = _NS("Shortcut");
    keyCol.width = 160.0;
    keyCol.resizingMask = NSTableColumnUserResizingMask;
    [_tableView addTableColumn:keyCol];

    tableScrollView.documentView = _tableView;
    [tableCard.contentStackView addArrangedSubview:tableScrollView];
    [tableScrollView.trailingAnchor constraintEqualToAnchor:tableCard.contentStackView.trailingAnchor].active = YES;
    [tableScrollView.heightAnchor constraintEqualToConstant:320.0].active = YES;

    // Buttons below table: Change Shortcut and Clear
    NSStackView *btnStack = [[NSStackView alloc] init];
    btnStack.translatesAutoresizingMaskIntoConstraints = NO;
    btnStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    btnStack.spacing = [MacLCDesign spacingS];

    _changeButton = [NSButton buttonWithTitle:_NS("Change Shortcut…")
                                      target:self
                                      action:@selector(changeShortcutAction:)];
    _changeButton.bezelStyle = NSBezelStyleRounded;
    [btnStack addArrangedSubview:_changeButton];

    _clearButton = [NSButton buttonWithTitle:_NS("Clear Shortcut")
                                     target:self
                                     action:@selector(clearShortcutAction:)];
    _clearButton.bezelStyle = NSBezelStyleRounded;
    [btnStack addArrangedSubview:_clearButton];

    [tableCard.contentStackView addArrangedSubview:btnStack];

    // Reset button
    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset All Shortcuts…")
                                            target:self
                                            action:@selector(resetSectionAction:)];
    resetBtn.translatesAutoresizingMaskIntoConstraints = NO;
    resetBtn.bezelStyle = NSBezelStyleRounded;
    [rootStack addArrangedSubview:resetBtn];

    [self loadSettings];
}

#pragma mark - Hotkey Data Loading

- (void)loadSettings
{
    _mediaKeysRow.checkboxButton.state = MacLCConfigGetInt("macosx-mediakeys", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    [_allDescriptions removeAllObjects];
    [_allNames removeAllObjects];
    [_allCurrentShortcuts removeAllObjects];
    [_allDefaultShortcuts removeAllObjects];

    module_t *p_main = module_get_main();
    if (p_main) {
        unsigned confsize;
        module_config_t *p_config = module_config_get(p_main, &confsize);
        if (p_config) {
            for (size_t i = 0; i < confsize; i++) {
                module_config_t *p_item = p_config + i;
                if (p_item->i_type == CONFIG_ITEM_KEY
                    && strncmp(p_item->psz_name, "global-", 7) != 0
                    && !EMPTY_STR(p_item->psz_text)) {
                    [_allDescriptions addObject:NSTR(p_item->psz_text)];
                    [_allNames addObject:toNSStr(p_item->psz_name)];

                    char *currVal = MacLCConfigGetPsz(p_item->psz_name);
                    [_allCurrentShortcuts addObject:currVal ? toNSStr(currVal) : @""];
                    if (currVal) free(currVal);

                    [_allDefaultShortcuts addObject:p_item->orig.psz ? toNSStr(p_item->orig.psz) : @""];
                }
            }
            module_config_free(p_config);
        }
    }

    [self updateFilter];
    self.hasUnsavedChanges = NO;
}

- (void)updateFilter
{
    [_filteredIndices removeAllObjects];
    NSString *search = _searchField.stringValue.lowercaseString;

    for (NSUInteger i = 0; i < _allDescriptions.count; i++) {
        if (search.length == 0) {
            [_filteredIndices addObject:@(i)];
        } else {
            NSString *desc = _allDescriptions[i].lowercaseString;
            NSString *key = _allCurrentShortcuts[i].lowercaseString;
            NSString *formattedKey = OSXStringKeyToString(_allCurrentShortcuts[i]).lowercaseString;
            if ([desc containsString:search] || [key containsString:search] || [formattedKey containsString:search]) {
                [_filteredIndices addObject:@(i)];
            }
        }
    }
    [_tableView reloadData];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    if (obj.object == _searchField) {
        [self updateFilter];
    }
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _filteredIndices.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_filteredIndices.count) return nil;
    NSUInteger realIdx = _filteredIndices[row].unsignedIntegerValue;

    NSString *identifier = tableColumn.identifier;
    NSTextField *label = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!label) {
        label = [NSTextField labelWithString:@""];
        label.identifier = identifier;
    }

    if ([identifier isEqualToString:@"action"]) {
        label.font = [MacLCDesign body];
        label.textColor = [MacLCDesign primaryLabel];
        label.stringValue = _allDescriptions[realIdx];
    } else {
        label.font = [MacLCDesign monospacedDigitBody];
        label.textColor = [MacLCDesign secondaryLabel];
        NSString *rawKey = _allCurrentShortcuts[realIdx];
        label.stringValue = rawKey.length > 0 ? OSXStringKeyToString(rawKey) : @"—";
    }

    return label;
}

- (void)tableDoubleClicked:(id)sender
{
    [self changeShortcutAction:sender];
}

#pragma mark - Shortcut Change Modal Sheet

- (void)changeShortcutAction:(id)sender
{
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filteredIndices.count) return;
    _editingIndex = _filteredIndices[row].integerValue;

    [self presentKeyChangeSheetForIndex:_editingIndex];
}

- (void)clearShortcutAction:(id)sender
{
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filteredIndices.count) return;
    NSUInteger realIdx = _filteredIndices[row].unsignedIntegerValue;

    _allCurrentShortcuts[realIdx] = @"";
    self.hasUnsavedChanges = YES;
    [_tableView reloadData];
}

- (void)presentKeyChangeSheetForIndex:(NSInteger)index
{
    _capturedKey = nil;

    // Sheet window
    _keyChangeSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 220)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    _keyChangeSheet.title = _NS("Change Shortcut");

    NSView *content = _keyChangeSheet.contentView;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = [MacLCDesign spacingM];

    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];

    _sheetActionLabel = [NSTextField labelWithString:[NSString stringWithFormat:_NS("Press new shortcut for: \"%@\""), _allDescriptions[index]]];
    _sheetActionLabel.font = [MacLCDesign headline];
    _sheetActionLabel.textColor = [MacLCDesign primaryLabel];
    _sheetActionLabel.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:_sheetActionLabel];

    _sheetShortcutLabel = [NSTextField labelWithString:_NS("Type a key combination…")];
    _sheetShortcutLabel.font = [MacLCDesign title2];
    _sheetShortcutLabel.textColor = [MacLCDesign accent];
    _sheetShortcutLabel.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:_sheetShortcutLabel];

    _sheetConflictLabel = [NSTextField labelWithString:@""];
    _sheetConflictLabel.font = [MacLCDesign caption];
    _sheetConflictLabel.textColor = [MacLCDesign warning];
    _sheetConflictLabel.alignment = NSTextAlignmentCenter;
    _sheetConflictLabel.hidden = YES;
    [stack addArrangedSubview:_sheetConflictLabel];

    NSStackView *btnStack = [[NSStackView alloc] init];
    btnStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    btnStack.spacing = [MacLCDesign spacingM];

    NSButton *cancelBtn = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(sheetCancel:)];
    cancelBtn.bezelStyle = NSBezelStyleRounded;
    cancelBtn.keyEquivalent = @"\e"; // Esc
    [btnStack addArrangedSubview:cancelBtn];

    NSButton *clearBtn = [NSButton buttonWithTitle:_NS("Clear") target:self action:@selector(sheetClear:)];
    clearBtn.bezelStyle = NSBezelStyleRounded;
    [btnStack addArrangedSubview:clearBtn];

    _sheetOkButton = [NSButton buttonWithTitle:_NS("OK") target:self action:@selector(sheetOk:)];
    _sheetOkButton.bezelStyle = NSBezelStyleRounded;
    _sheetOkButton.keyEquivalent = @"\r"; // Enter
    _sheetOkButton.enabled = NO;
    [btnStack addArrangedSubview:_sheetOkButton];

    [stack addArrangedSubview:btnStack];

    // Install key event monitor for sheet
    __weak typeof(self) weakSelf = self;
    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if ([weakSelf handleSheetKeyEvent:event]) {
            return nil; // Event consumed
        }
        return event;
    }];

    [self.view.window beginSheet:_keyChangeSheet completionHandler:nil];
}

- (BOOL)handleSheetKeyEvent:(NSEvent *)event
{
    NSMutableString *keyStr = [NSMutableString string];
    NSUInteger flags = event.modifierFlags;

    if (flags & NSEventModifierFlagCommand) [keyStr appendString:@"Command-"];
    if (flags & NSEventModifierFlagControl) [keyStr appendString:@"Ctrl-"];
    if (flags & NSEventModifierFlagShift)   [keyStr appendString:@"Shift-"];
    if (flags & NSEventModifierFlagOption)  [keyStr appendString:@"Alt-"];

    NSString *chars = event.characters;
    if (chars.length == 0) return NO;
    unichar keyChar = [chars characterAtIndex:0];

    if (keyChar == NSUpArrowFunctionKey) [keyStr appendString:@"Up"];
    else if (keyChar == NSDownArrowFunctionKey) [keyStr appendString:@"Down"];
    else if (keyChar == NSLeftArrowFunctionKey) [keyStr appendString:@"Left"];
    else if (keyChar == NSRightArrowFunctionKey) [keyStr appendString:@"Right"];
    else if (keyChar >= NSF1FunctionKey && keyChar <= NSF12FunctionKey) {
        [keyStr appendFormat:@"F%d", (int)(keyChar - NSF1FunctionKey + 1)];
    }
    else if (keyChar == ' ') [keyStr appendString:@"Space"];
    else if (keyChar == NSTabCharacter) [keyStr appendString:@"Tab"];
    else if (keyChar == NSCarriageReturnCharacter || keyChar == NSEnterCharacter) [keyStr appendString:@"Enter"];
    else if (keyChar == NSDeleteCharacter) [keyStr appendString:@"Delete"];
    else if (keyChar == NSBackspaceCharacter) [keyStr appendString:@"Backspace"];
    else if (keyChar == 0x1B) return NO; // Allow Esc to trigger Cancel button
    else {
        NSString *plain = [event.charactersIgnoringModifiers lowercaseString];
        if (plain.length > 0) [keyStr appendString:plain];
        else return NO;
    }

    _capturedKey = [keyStr copy];
    _sheetShortcutLabel.stringValue = OSXStringKeyToString(_capturedKey);

    // Check conflicts
    NSInteger conflictIdx = NSNotFound;
    for (NSUInteger i = 0; i < _allCurrentShortcuts.count; i++) {
        if (i != (NSUInteger)_editingIndex && [_allCurrentShortcuts[i] isEqualToString:_capturedKey]) {
            conflictIdx = (NSInteger)i;
            break;
        }
    }

    if (conflictIdx != NSNotFound) {
        _sheetConflictLabel.stringValue = [NSString stringWithFormat:_NS("Will replace shortcut for: \"%@\""), _allDescriptions[conflictIdx]];
        _sheetConflictLabel.hidden = NO;
    } else {
        _sheetConflictLabel.hidden = YES;
    }

    _sheetOkButton.enabled = YES;
    return YES;
}

- (void)sheetCancel:(id)sender
{
    [self closeSheet];
}

- (void)sheetClear:(id)sender
{
    _allCurrentShortcuts[_editingIndex] = @"";
    self.hasUnsavedChanges = YES;
    [_tableView reloadData];
    [self closeSheet];
}

- (void)sheetOk:(id)sender
{
    if (_capturedKey.length > 0) {
        // Clear conflicting entry if present
        for (NSUInteger i = 0; i < _allCurrentShortcuts.count; i++) {
            if (i != (NSUInteger)_editingIndex && [_allCurrentShortcuts[i] isEqualToString:_capturedKey]) {
                _allCurrentShortcuts[i] = @"";
            }
        }
        _allCurrentShortcuts[_editingIndex] = _capturedKey;
        self.hasUnsavedChanges = YES;
        [_tableView reloadData];
    }
    [self closeSheet];
}

- (void)closeSheet
{
    if (_eventMonitor) {
        [NSEvent removeMonitor:_eventMonitor];
        _eventMonitor = nil;
    }
    if (_keyChangeSheet) {
        [self.view.window endSheet:_keyChangeSheet];
        [_keyChangeSheet orderOut:nil];
        _keyChangeSheet = nil;
    }
}

- (void)resetSectionAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Reset Shortcuts");
    alert.informativeText = _NS("Are you sure you want to restore all keyboard shortcuts to their default assignments?");
    [alert addButtonWithTitle:_NS("Reset")];
    [alert addButtonWithTitle:_NS("Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf resetToDefaults];
        }
    }];
}

#pragma mark - Settings Operations

- (void)applyChanges
{
    MacLCConfigPutInt("macosx-mediakeys", _mediaKeysRow.checkboxButton.state == NSControlStateValueOn);

    for (NSUInteger i = 0; i < _allNames.count; i++) {
        MacLCConfigPutPsz([_allNames[i] UTF8String], [_allCurrentShortcuts[i] UTF8String]);
    }
    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    module_config_t *item = config_FindConfig("macosx-mediakeys");
    if (item) MacLCConfigPutInt("macosx-mediakeys", item->orig.i);

    for (NSUInteger i = 0; i < _allNames.count; i++) {
        _allCurrentShortcuts[i] = _allDefaultShortcuts[i];
    }

    _mediaKeysRow.checkboxButton.state = item && item->orig.i ? NSControlStateValueOn : NSControlStateValueOff;
    [_tableView reloadData];
    self.hasUnsavedChanges = YES;
}

@end
