/*****************************************************************************
 * MacLCLibraryFoldersController.m: choose the folders the library watches
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#import "medialib/shell/MacLCLibraryFoldersController.h"

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryDataTypes.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "theme/MacLCDesign.h"

@interface MacLCLibraryFoldersController () <NSTableViewDataSource, NSTableViewDelegate>
{
    NSTableView *_tableView;
    NSSegmentedControl *_addRemoveControl;
    NSArray<VLCMediaLibraryEntryPoint *> *_folders;
    __weak NSWindow *_parentWindow;
}
@end

@implementation MacLCLibraryFoldersController

+ (instancetype)sharedController
{
    static MacLCLibraryFoldersController *sharedController;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedController = [[MacLCLibraryFoldersController alloc] init];
    });
    return sharedController;
}

- (instancetype)init
{
    NSPanel * const panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 360)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
    panel.title = _NS("Library Folders");
    self = [super initWithWindow:panel];
    if (self) {
        _folders = @[];
        [self buildContent];
        NSNotificationCenter * const center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(foldersChanged:)
                       name:MacLCLibraryStoreFoldersDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(foldersChanged:)
                       name:MacLCLibraryStoreIndexingDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)buildContent
{
    NSView * const content = self.window.contentView;

    NSTextField * const title = [NSTextField labelWithString:_NS("Library Folders")];
    title.font = MacLCDesign.headline;
    NSTextField * const explanation = [NSTextField wrappingLabelWithString:
        _NS("MacLC adds the movies, shows and music it finds in these folders. Nothing leaves your Mac.")];
    explanation.font = MacLCDesign.body;
    explanation.textColor = NSColor.secondaryLabelColor;

    _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 480, 200)];
    _tableView.style = NSTableViewStyleFullWidth;
    _tableView.headerView = nil;
    _tableView.rowHeight = 40.0;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = YES;
    [_tableView addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"folder"]];
    _tableView.tableColumns.firstObject.resizingMask = NSTableColumnAutoresizingMask;
    _tableView.dataSource = self;
    _tableView.delegate = self;

    NSScrollView * const scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.documentView = _tableView;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    _addRemoveControl = [NSSegmentedControl segmentedControlWithImages:@[
        [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:_NS("Add Folder")],
        [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:_NS("Remove Folder")],
    ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(addRemovePressed:)];
    _addRemoveControl.segmentStyle = NSSegmentStyleSmallSquare;
    [_addRemoveControl setToolTip:_NS("Add Folder") forSegment:0];
    [_addRemoveControl setToolTip:_NS("Remove Folder") forSegment:1];

    NSButton * const rescan = [NSButton buttonWithTitle:_NS("Rescan") target:self action:@selector(rescan:)];
    NSButton * const done = [NSButton buttonWithTitle:_NS("Done") target:self action:@selector(done:)];
    done.keyEquivalent = @"\r";

    NSStackView * const buttons = [NSStackView stackViewWithViews:@[rescan, done]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 12.0;

    for (NSView * const view in @[title, explanation, scrollView, _addRemoveControl, buttons]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:20.0],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [explanation.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6.0],
        [explanation.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [explanation.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0],
        [scrollView.topAnchor constraintEqualToAnchor:explanation.bottomAnchor constant:14.0],
        [scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0],
        [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:160.0],
        [_addRemoveControl.topAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-1.0],
        [_addRemoveControl.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [buttons.topAnchor constraintEqualToAnchor:_addRemoveControl.bottomAnchor constant:16.0],
        [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20.0],
    ]];
}

// MARK: - Presentation

- (void)beginSheetForWindow:(NSWindow *)window
{
    _parentWindow = window;
    [self reload];
    if (window != nil) {
        [window beginSheet:self.window completionHandler:nil];
    } else {
        [self.window center];
        [self.window makeKeyAndOrderFront:nil];
    }
}

- (void)done:(id)sender
{
    NSWindow * const sheetParent = self.window.sheetParent;
    if (sheetParent != nil) {
        [sheetParent endSheet:self.window];
    } else {
        [self.window orderOut:sender];
    }
}

- (void)chooseFoldersToAddForWindow:(nullable NSWindow *)window
{
    NSOpenPanel * const panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = YES;
    panel.prompt = _NS("Add");
    panel.message = _NS("Choose folders with movies, shows or music.");
    void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
        if (response != NSModalResponseOK) {
            return;
        }
        for (NSURL * const url in panel.URLs) {
            [MacLCLibraryStore.sharedStore addFolderAtURL:url];
        }
    };
    if (window != nil) {
        [panel beginSheetModalForWindow:window completionHandler:handler];
    } else {
        handler([panel runModal]);
    }
}

- (void)addRemovePressed:(NSSegmentedControl *)sender
{
    if (sender.selectedSegment == 0) {
        [self chooseFoldersToAddForWindow:self.window];
        return;
    }
    NSIndexSet * const rows = _tableView.selectedRowIndexes;
    if (rows.count == 0) {
        return;
    }
    NSArray<VLCMediaLibraryEntryPoint *> * const folders = [_folders objectsAtIndexes:rows];
    NSAlert * const alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    NSString * const name = folders.count == 1
        ? [NSURL URLWithString:folders.firstObject.MRL].lastPathComponent.stringByRemovingPercentEncoding
        : nil;
    alert.messageText = name != nil
        ? [NSString stringWithFormat:_NS("Remove “%@” from the library?"), name]
        : _NS("Remove These Folders from the Library?");
    alert.informativeText = _NS("The files stay on your Mac.");
    NSButton * const remove = [alert addButtonWithTitle:_NS("Remove")];
    remove.hasDestructiveAction = YES;
    remove.keyEquivalent = @"";
    [alert addButtonWithTitle:_NS("Cancel")].keyEquivalent = @"\r";
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) {
            return;
        }
        for (VLCMediaLibraryEntryPoint * const folder in folders) {
            NSURL * const url = [NSURL URLWithString:folder.MRL];
            if (url != nil) {
                [MacLCLibraryStore.sharedStore removeFolderAtURL:url];
            }
        }
    }];
}

- (void)rescan:(id)sender
{
    [MacLCLibraryStore.sharedStore rescanFolders];
}

// MARK: - Contents

- (void)foldersChanged:(NSNotification *)notification
{
    [self reload];
}

- (void)reload
{
    _folders = MacLCLibraryStore.sharedStore.folders ?: @[];
    [_tableView reloadData];
    [_addRemoveControl setEnabled:_folders.count > 0 forSegment:1];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)_folders.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"MacLCFolderCell" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 480, 40)];
        cell.identifier = @"MacLCFolderCell";
        NSImageView * const icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        NSTextField * const name = [NSTextField labelWithString:@""];
        name.font = MacLCDesign.body;
        NSTextField * const path = [NSTextField labelWithString:@""];
        path.font = MacLCDesign.subheadline;
        path.textColor = NSColor.secondaryLabelColor;
        path.lineBreakMode = NSLineBreakByTruncatingMiddle;
        path.tag = 1;
        NSStackView * const text = [NSStackView stackViewWithViews:@[name, path]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 0.0;
        NSStackView * const rowStack = [NSStackView stackViewWithViews:@[icon, text]];
        rowStack.spacing = 8.0;
        rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:rowStack];
        [NSLayoutConstraint activateConstraints:@[
            [icon.widthAnchor constraintEqualToConstant:24.0],
            [icon.heightAnchor constraintEqualToConstant:24.0],
            [rowStack.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6.0],
            [rowStack.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-6.0],
            [rowStack.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        cell.imageView = icon;
        cell.textField = name;
    }
    VLCMediaLibraryEntryPoint * const folder = _folders[(NSUInteger)row];
    NSURL * const url = [NSURL URLWithString:folder.MRL];
    NSString * const path = url.isFileURL ? url.path : folder.decodedMRL;
    cell.textField.stringValue = url.lastPathComponent.stringByRemovingPercentEncoding ?: path ?: @"";
    NSTextField * const pathField = [cell viewWithTag:1];
    pathField.stringValue = folder.isPresent ? (path ?: @"") : [NSString stringWithFormat:_NS("%@ (not connected)"), path ?: @""];
    cell.imageView.image = path != nil && url.isFileURL
        ? [NSWorkspace.sharedWorkspace iconForFile:path]
        : [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:nil];
    return cell;
}

@end
