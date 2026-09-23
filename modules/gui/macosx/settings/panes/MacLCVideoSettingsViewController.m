/*****************************************************************************
 * MacLCVideoSettingsViewController.m: Video Settings Pane for MacLC
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

#import "settings/panes/MacLCVideoSettingsViewController.h"
#import "settings/MacLCConfigSafe.h"
#import "frameinterp/MacLCFrameInterpolation.h"
#import "settings/MacLCSettingsRow.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_configuration.h>
#include <math.h>

@interface MacLCVideoSettingsViewController ()
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, assign) BOOL hasUnsavedChanges;

// Rows
@property (nonatomic, strong) MacLCSettingsRow *videoEnableRow;
@property (nonatomic, strong) MacLCSettingsRow *targetScreenRow;
@property (nonatomic, strong) MacLCSettingsRow *onTopRow;
@property (nonatomic, strong) MacLCSettingsRow *autoResizeRow;
@property (nonatomic, strong) MacLCSettingsRow *pauseMinimizedRow;

@property (nonatomic, strong) MacLCSettingsRow *startFullscreenRow;
@property (nonatomic, strong) MacLCSettingsRow *nativeFullscreenRow;
@property (nonatomic, strong) MacLCSettingsRow *blackScreenRow;
@property (nonatomic, strong) MacLCSettingsRow *dimKeyboardRow;

@property (nonatomic, strong) MacLCSettingsRow *deinterlaceRow;
@property (nonatomic, strong) MacLCSettingsRow *deinterlaceModeRow;
@property (nonatomic, strong) MacLCSettingsRow *aspectRatioRow;
@property (nonatomic, strong) MacLCSettingsRow *cropRatioRow;
@property (nonatomic, strong) MacLCSettingsRow *lockAspectRow;

@property (nonatomic, strong) MacLCSettingsRow *interpolationRow;
@property (nonatomic, strong) MacLCSettingsRow *interpolationTargetRow;
@property (nonatomic, strong) MacLCSettingsRow *interpolationOverrunRow;
@property (nonatomic, strong) MacLCSettingsRow *interpolationRifeRow;
@property (nonatomic, strong) MacLCSettingsRow *interpolationRifeScaleRow;
@property (nonatomic, strong) MacLCSettingsRow *interpolationRifeModelRow;
@property (nonatomic, strong) MacLCSettingsRow *interpolationSvpPathRow;

@property (nonatomic, strong) MacLCSettingsRow *snapFolderRow;
@property (nonatomic, strong) MacLCSettingsRow *snapPrefixRow;
@property (nonatomic, strong) MacLCSettingsRow *snapFormatRow;
@property (nonatomic, strong) MacLCSettingsRow *snapSequentialRow;

@end

@implementation MacLCVideoSettingsViewController

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _p_intf = intf;
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
    return _NS("Video");
}

- (NSString *)paneSymbolName
{
    return @"display";
}

- (NSString *)paneIdentifier
{
    return @"video";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"video", @"screen", @"display", @"fullscreen", @"black", @"dim",
        @"keyboard", @"deinterlace", @"interlace", @"aspect", @"ratio",
        @"crop", @"snapshot", @"screenshot", @"prefix", @"format",
        @"png", @"jpg", @"sequential", @"on top", @"resize", @"pause",
        @"video", @"macosx-vdev", @"video-on-top", @"macosx-video-autoresize",
        @"macosx-pause-minimized", @"fullscreen", @"macosx-nativefullscreenmode",
        @"macosx-black", @"macosx-dim-keyboard", @"deinterlace", @"deinterlace-mode",
        @"aspect-ratio", @"crop", @"macosx-lock-aspect-ratio", @"snapshot-path",
        @"snapshot-prefix", @"snapshot-format", @"snapshot-sequential"
    ];
}

#pragma mark - View Lifecycle & Layout

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 1100)];
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

    // Card 1: Video Display
    MacLCCardView *displayCard = [MacLCCardView cardViewWithTitle:_NS("Video Display")];
    displayCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:displayCard];
    [displayCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _videoEnableRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Enable Video")
                                                 explanation:_NS("Render visual output during video file playback.")
                                                       state:YES
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _videoEnableRow.defaultHint = _NS("Default: On");
    [displayCard.contentStackView addArrangedSubview:_videoEnableRow];

    NSMutableArray<NSString *> *screenTitles = [NSMutableArray arrayWithObject:_NS("Default")];
    NSMutableArray<NSNumber *> *screenTags = [NSMutableArray arrayWithObject:@0];
    NSArray<NSScreen *> *screens = [NSScreen screens];
    for (NSUInteger i = 0; i < screens.count; i++) {
        NSRect r = screens[i].frame;
        [screenTitles addObject:[NSString stringWithFormat:@"%@ %lu (%dx%d)",
                                 _NS("Screen"), (unsigned long)(i + 1), (int)r.size.width, (int)r.size.height]];
        [screenTags addObject:@(i + 1)];
    }

    _targetScreenRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Target Display")
                                               explanation:_NS("Monitor used for video display when entering fullscreen.")
                                                     items:screenTitles
                                                      tags:screenTags
                                             selectedIndex:0
                                                    action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _targetScreenRow.defaultHint = _NS("Default: Default");
    [displayCard.contentStackView addArrangedSubview:_targetScreenRow];

    _onTopRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Keep on Top")
                                           explanation:_NS("Keep the video window above other running application windows.")
                                                 state:NO
                                                action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _onTopRow.defaultHint = _NS("Default: Off");
    [displayCard.contentStackView addArrangedSubview:_onTopRow];

    _autoResizeRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Resize Window to Video Size")
                                                explanation:_NS("Automatically adjust the window dimensions to match the source video resolution.")
                                                      state:YES
                                                     action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _autoResizeRow.defaultHint = _NS("Default: On");
    [displayCard.contentStackView addArrangedSubview:_autoResizeRow];

    _pauseMinimizedRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Pause When Minimized")
                                                    explanation:_NS("Automatically pause video playback when the player window is minimized.")
                                                          state:NO
                                                         action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _pauseMinimizedRow.defaultHint = _NS("Default: Off");
    [displayCard.contentStackView addArrangedSubview:_pauseMinimizedRow];

    // Card 2: Fullscreen Behaviour
    MacLCCardView *fullscreenCard = [MacLCCardView cardViewWithTitle:_NS("Fullscreen Behaviour")];
    fullscreenCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:fullscreenCard];
    [fullscreenCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _startFullscreenRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Start in Fullscreen")
                                                     explanation:_NS("Automatically expand newly played videos to fill the entire screen.")
                                                           state:NO
                                                          action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _startFullscreenRow.defaultHint = _NS("Default: Off");
    [fullscreenCard.contentStackView addArrangedSubview:_startFullscreenRow];

    _nativeFullscreenRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Native macOS Fullscreen")
                                                      explanation:_NS("Use macOS standard Spaces fullscreen mode rather than a custom window overlay.")
                                                            state:YES
                                                           action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        weakSelf.blackScreenRow.enabled = !checked;
    }];
    _nativeFullscreenRow.defaultHint = _NS("Default: On");
    [fullscreenCard.contentStackView addArrangedSubview:_nativeFullscreenRow];

    _blackScreenRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Black Other Displays")
                                                 explanation:_NS("Blank connected secondary screens with solid black during fullscreen playback.")
                                                       state:NO
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _blackScreenRow.defaultHint = _NS("Default: Off");
    [fullscreenCard.contentStackView addArrangedSubview:_blackScreenRow];

    _dimKeyboardRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Dim Keyboard Backlight")
                                                 explanation:_NS("Turn off MacBook keyboard backlight illumination while video plays in fullscreen.")
                                                       state:NO
                                                      action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _dimKeyboardRow.defaultHint = _NS("Default: Off");
    [fullscreenCard.contentStackView addArrangedSubview:_dimKeyboardRow];

    // Card 3: Deinterlacing & Aspect Ratio
    MacLCCardView *aspectCard = [MacLCCardView cardViewWithTitle:_NS("Deinterlacing & Proportions")];
    aspectCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:aspectCard];
    [aspectCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _deinterlaceRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Deinterlacing")
                                              explanation:_NS("Eliminate horizontal comb artifacts from broadcast and DVD interlaced content.")
                                                    items:@[_NS("Automatic"), _NS("On"), _NS("Off")]
                                                     tags:@[@-1, @1, @0]
                                            selectedIndex:0
                                                   action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _deinterlaceRow.defaultHint = _NS("Default: Automatic");
    [aspectCard.contentStackView addArrangedSubview:_deinterlaceRow];

    _deinterlaceModeRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Deinterlace Mode")
                                                  explanation:_NS("Algorithm used to blend or interpolate alternating video field lines.")
                                                        items:@[_NS("Automatic"), _NS("Discard"), _NS("Blend"), _NS("Bob"), _NS("Linear"), _NS("Yadif"), _NS("Yadif (2x)")]
                                                         tags:@[@0, @1, @2, @3, @4, @5, @6]
                                                selectedIndex:0
                                                       action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _deinterlaceModeRow.defaultHint = _NS("Default: Automatic");
    [aspectCard.contentStackView addArrangedSubview:_deinterlaceModeRow];

    NSArray<NSString *> *ratios = @[_NS("Default"), @"16:9", @"16:10", @"4:3", @"2.35:1", @"1:1"];

    _aspectRatioRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Default Aspect Ratio")
                                              explanation:_NS("Force newly opened videos to display at a specific width-to-height proportion.")
                                                    items:ratios
                                                     tags:nil
                                            selectedIndex:0
                                                   action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _aspectRatioRow.defaultHint = _NS("Default: Default");
    [aspectCard.contentStackView addArrangedSubview:_aspectRatioRow];

    _cropRatioRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Default Crop Ratio")
                                            explanation:_NS("Crop frame borders to conform to a specific ratio without stretching.")
                                                  items:ratios
                                                   tags:nil
                                          selectedIndex:0
                                                 action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _cropRatioRow.defaultHint = _NS("Default: Default");
    [aspectCard.contentStackView addArrangedSubview:_cropRatioRow];

    _lockAspectRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Lock Aspect Ratio on Resize")
                                                explanation:_NS("Maintain correct width-to-height proportions when manually resizing windows.")
                                                      state:YES
                                                     action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _lockAspectRow.defaultHint = _NS("Default: On");
    [aspectCard.contentStackView addArrangedSubview:_lockAspectRow];

    // Card 4: Frame Interpolation
    MacLCCardView *interpolationCard =
        [MacLCCardView cardViewWithTitle:_NS("Frame Interpolation")];
    interpolationCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:interpolationCard];
    [interpolationCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _interpolationRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Motion Interpolation")
                                                explanation:_NS("Synthesise intermediate frames so motion matches the refresh rate of the display. Automatic picks the best method that still runs in real time; Quality costs about twice what Balanced does without looking better.")
                                                      items:@[_NS("Off"), _NS("Automatic"),
                                                              _NS("Quality (optical flow)"),
                                                              _NS("Balanced (optical flow)"),
                                                              _NS("Low latency (up to 720p)"),
                                                              _NS("Motion compensation"),
                                                              _NS("Blend"),
                                                              _NS("SmoothVideo Project"),
                                                              _NS("RIFE neural network")]
                                                       tags:@[@-1, @0, @1, @2, @3, @4, @5, @6, @7]
                                              selectedIndex:0
                                                     action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
        [weakSelf updateInterpolationRowEnablement];
    }];
    _interpolationRow.defaultHint = _NS("Default: Off");
    [interpolationCard.contentStackView addArrangedSubview:_interpolationRow];

    _interpolationTargetRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Target Frame Rate")
                                                      explanation:_NS("Frame rate to aim for. Matching the display picks the largest whole multiple of the source the screen can show.")
                                                            items:@[_NS("Match the Display"), _NS("60 fps"),
                                                                    _NS("120 fps"), _NS("Twice the Source")]
                                                             tags:@[@0, @1, @2, @3]
                                                    selectedIndex:0
                                                           action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _interpolationTargetRow.defaultHint = _NS("Default: Match the Display");
    [interpolationCard.contentStackView addArrangedSubview:_interpolationTargetRow];

    _interpolationOverrunRow = [MacLCSettingsRow popUpRowWithTitle:_NS("When Too Slow")
                                                       explanation:_NS("What to do when a pass no longer fits in the time one source frame lasts.")
                                                             items:@[_NS("Fall Back to a Cheaper Method"),
                                                                     _NS("Stop Interpolating"),
                                                                     _NS("Keep Going")]
                                                              tags:@[@0, @1, @2]
                                                     selectedIndex:0
                                                            action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _interpolationOverrunRow.defaultHint = _NS("Default: Fall Back to a Cheaper Method");
    [interpolationCard.contentStackView addArrangedSubview:_interpolationOverrunRow];

    _interpolationRifeRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Use the RIFE Neural Network")
                                                       explanation:_NS("Replaces the motion vectors of the SmoothVideo Project engine with the neural network. The RIFE engine always uses the network whatever this says.")
                                                             state:NO
                                                            action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
        [weakSelf updateInterpolationRowEnablement];
    }];
    _interpolationRifeRow.defaultHint = _NS("Default: Off");
    [interpolationCard.contentStackView addArrangedSubview:_interpolationRifeRow];

    _interpolationRifeScaleRow = [MacLCSettingsRow popUpRowWithTitle:_NS("RIFE Detail Level")
                                                         explanation:_NS("The fraction of the picture motion is computed at. Half costs about a third as much, which is what lets 4K keep up.")
                                                               items:@[_NS("Full picture"),
                                                                       _NS("Three quarters"),
                                                                       _NS("Half")]
                                                                tags:@[@100, @75, @50]
                                                       selectedIndex:0
                                                              action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _interpolationRifeScaleRow.defaultHint = _NS("Default: Full picture");
    [interpolationCard.contentStackView addArrangedSubview:_interpolationRifeScaleRow];

    _interpolationRifeModelRow = [MacLCSettingsRow pathPickerRowWithTitle:_NS("RIFE Model")
                                                              explanation:_NS("The folder or Core ML package holding the network. Left empty, MacLC looks in its own Resources folder and then in Application Support.")
                                                                     path:@""
                                                              chooseTitle:_NS("Choose…")
                                                             chooseAction:^(MacLCSettingsRow *row) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = YES;
        panel.allowsMultipleSelection = NO;
        panel.prompt = _NS("Select");
        [panel beginSheetModalForWindow:weakSelf.view.window completionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK && panel.URL.path) {
                row.textField.stringValue = panel.URL.path;
                weakSelf.hasUnsavedChanges = YES;
            }
        }];
    }];
    _interpolationRifeModelRow.textChangedHandler = ^(NSString *text) {
        weakSelf.hasUnsavedChanges = YES;
    };
    [interpolationCard.contentStackView addArrangedSubview:_interpolationRifeModelRow];

    _interpolationSvpPathRow = [MacLCSettingsRow pathPickerRowWithTitle:_NS("SmoothVideo Project Folder")
                                                            explanation:_NS("Where SVP 4 Mac is installed. Left empty, the Applications folder is used. MacLC uses the copy the user installed and does not carry it.")
                                                                   path:@""
                                                            chooseTitle:_NS("Choose…")
                                                           chooseAction:^(MacLCSettingsRow *row) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = NO;
        panel.allowsMultipleSelection = NO;
        panel.prompt = _NS("Select");
        [panel beginSheetModalForWindow:weakSelf.view.window completionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK && panel.URL.path) {
                row.textField.stringValue = panel.URL.path;
                weakSelf.hasUnsavedChanges = YES;
            }
        }];
    }];
    _interpolationSvpPathRow.textChangedHandler = ^(NSString *text) {
        weakSelf.hasUnsavedChanges = YES;
    };
    [interpolationCard.contentStackView addArrangedSubview:_interpolationSvpPathRow];

    // Card 4: Video Snapshots
    MacLCCardView *snapCard = [MacLCCardView cardViewWithTitle:_NS("Video Snapshots")];
    snapCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:snapCard];
    [snapCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    _snapFolderRow = [MacLCSettingsRow pathPickerRowWithTitle:_NS("Snapshot Folder")
                                                  explanation:_NS("Directory where captured screenshot image files are stored.")
                                                         path:@""
                                                  chooseTitle:_NS("Choose…")
                                                 chooseAction:^(MacLCSettingsRow *row) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = NO;
        panel.allowsMultipleSelection = NO;
        panel.prompt = _NS("Select");
        [panel beginSheetModalForWindow:weakSelf.view.window completionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK && panel.URL.path) {
                row.textField.stringValue = panel.URL.path;
                weakSelf.hasUnsavedChanges = YES;
            }
        }];
    }];
    [snapCard.contentStackView addArrangedSubview:_snapFolderRow];

    _snapPrefixRow = [MacLCSettingsRow textFieldRowWithTitle:_NS("Filename Prefix")
                                                 explanation:_NS("Initial text added to the beginning of saved snapshot filenames.")
                                                        text:@"maclcsnap-"
                                                 placeholder:@"maclcsnap-"
                                                    isSecure:NO
                                                      action:^(NSString *text) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _snapPrefixRow.defaultHint = _NS("Default: maclcsnap-");
    [snapCard.contentStackView addArrangedSubview:_snapPrefixRow];

    _snapFormatRow = [MacLCSettingsRow popUpRowWithTitle:_NS("Snapshot Format")
                                             explanation:_NS("Image compression and encoding format used for captured screenshots.")
                                                   items:@[@"png", @"jpg", @"tiff"]
                                                    tags:@[@0, @1, @2]
                                           selectedIndex:0
                                                  action:^(NSInteger selectedIndex, NSInteger tag) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _snapFormatRow.defaultHint = _NS("Default: png");
    [snapCard.contentStackView addArrangedSubview:_snapFormatRow];

    _snapSequentialRow = [MacLCSettingsRow checkboxRowWithTitle:_NS("Sequential Numbering")
                                                    explanation:_NS("Name screenshots with incrementing numbers (00001, 00002) instead of dates.")
                                                          state:NO
                                                         action:^(BOOL checked) {
        weakSelf.hasUnsavedChanges = YES;
    }];
    _snapSequentialRow.defaultHint = _NS("Default: Off");
    [snapCard.contentStackView addArrangedSubview:_snapSequentialRow];

    // Reset button
    NSButton *resetBtn = [NSButton buttonWithTitle:_NS("Reset Video Settings…")
                                            target:self
                                            action:@selector(resetSectionAction:)];
    resetBtn.translatesAutoresizingMaskIntoConstraints = NO;
    resetBtn.bezelStyle = NSBezelStyleRounded;
    [rootStack addArrangedSubview:resetBtn];

    [self loadSettings];
}

- (void)resetSectionAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Reset Video Settings");
    alert.informativeText = _NS("Are you sure you want to reset all Video options to their default values?");
    [alert addButtonWithTitle:_NS("Reset")];
    [alert addButtonWithTitle:_NS("Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf resetToDefaults];
        }
    }];
}

- (void)updateInterpolationRowEnablement
{
    const NSInteger engine = _interpolationRow.popUpButton.selectedTag;
    const BOOL active = (engine >= 0);
    _interpolationTargetRow.enabled = active;
    _interpolationOverrunRow.enabled = active;

    const BOOL isSVP = (engine == 6);
    const BOOL isRIFE = (engine == 7);
    const BOOL rifeChecked = (_interpolationRifeRow.checkboxButton.state == NSControlStateValueOn);

    _interpolationRifeRow.enabled = isSVP;
    _interpolationRifeScaleRow.enabled = isRIFE || (isSVP && rifeChecked);
    _interpolationRifeModelRow.enabled = isRIFE || (isSVP && rifeChecked);
    _interpolationSvpPathRow.enabled = isSVP;

    if (active) {
        NSString * const reason =
            [MacLCFrameInterpolation unavailabilityReasonForEngine:(MacLCFrameInterpolationEngine)engine];
        if (reason != nil) {
            _interpolationRow.warning = YES;
            _interpolationRow.defaultHint = reason;
        } else {
            _interpolationRow.warning = NO;
            _interpolationRow.defaultHint = nil;
        }
    } else {
        _interpolationRow.warning = NO;
        _interpolationRow.defaultHint = _NS("Default: Off");
    }
}

#pragma mark - Settings Operations

- (void)loadSettings
{
    _videoEnableRow.checkboxButton.state = MacLCConfigGetInt("video", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    [_targetScreenRow.popUpButton selectItemWithTag:MacLCConfigGetInt("macosx-vdev", 0)];
    _onTopRow.checkboxButton.state = MacLCConfigGetInt("video-on-top", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _autoResizeRow.checkboxButton.state = MacLCConfigGetInt("macosx-video-autoresize", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _pauseMinimizedRow.checkboxButton.state = MacLCConfigGetInt("macosx-pause-minimized", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    _startFullscreenRow.checkboxButton.state = MacLCConfigGetInt("fullscreen", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    BOOL nativeFS = MacLCConfigGetInt("macosx-nativefullscreenmode", 0) != 0;
    _nativeFullscreenRow.checkboxButton.state = nativeFS ? NSControlStateValueOn : NSControlStateValueOff;
    _blackScreenRow.checkboxButton.state = MacLCConfigGetInt("macosx-black", 0) ? NSControlStateValueOn : NSControlStateValueOff;
    _blackScreenRow.enabled = !nativeFS;
    _dimKeyboardRow.checkboxButton.state = MacLCConfigGetInt("macosx-dim-keyboard", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    [_deinterlaceRow.popUpButton selectItemWithTag:MacLCConfigGetInt("deinterlace", 0)];

    char *mode = MacLCConfigGetPsz("deinterlace-mode");
    NSString *modeStr = mode ? toNSStr(mode) : @"auto";
    free(mode);
    NSArray *modes = @[@"auto", @"discard", @"blend", @"bob", @"linear", @"yadif", @"yadif2x"];
    NSUInteger mIdx = [modes indexOfObject:modeStr];
    [_deinterlaceModeRow.popUpButton selectItemAtIndex:(mIdx != NSNotFound) ? (NSInteger)mIdx : 0];

    const BOOL interpolating = MacLCFrameInterpolation.isEnabled;
    [_interpolationRow.popUpButton selectItemWithTag:
        interpolating ? MacLCConfigGetInt("maclc-frc-engine", 0) : -1];
    [_interpolationTargetRow.popUpButton selectItemWithTag:
        MacLCConfigGetInt("maclc-frc-target", 0)];
    [_interpolationOverrunRow.popUpButton selectItemWithTag:
        MacLCConfigGetInt("maclc-frc-overrun", 0)];

    _interpolationRifeRow.checkboxButton.state =
        MacLCConfigGetInt("maclc-frc-rife", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    const float rifeScale = MacLCConfigGetFloat("maclc-frc-rife-scale", 1.0f);
    NSInteger scaleTag = (NSInteger)roundf(rifeScale * 100.0f);
    if (scaleTag != 50 && scaleTag != 75 && scaleTag != 100) {
        scaleTag = 100;
    }
    [_interpolationRifeScaleRow.popUpButton selectItemWithTag:scaleTag];

    char * const rifeModel = MacLCConfigGetPsz("maclc-frc-rife-model");
    _interpolationRifeModelRow.textField.stringValue = rifeModel ? toNSStr(rifeModel) : @"";
    free(rifeModel);

    char * const svpPath = MacLCConfigGetPsz("maclc-frc-svp-path");
    _interpolationSvpPathRow.textField.stringValue = svpPath ? toNSStr(svpPath) : @"";
    free(svpPath);

    [self updateInterpolationRowEnablement];

    char *aspect = MacLCConfigGetPsz("aspect-ratio");
    NSString *aspectStr = aspect ? toNSStr(aspect) : @"";
    free(aspect);
    [_aspectRatioRow.popUpButton selectItemWithTitle:aspectStr.length > 0 ? aspectStr : _NS("Default")];

    char *crop = MacLCConfigGetPsz("crop");
    NSString *cropStr = crop ? toNSStr(crop) : @"";
    free(crop);
    [_cropRatioRow.popUpButton selectItemWithTitle:cropStr.length > 0 ? cropStr : _NS("Default")];

    _lockAspectRow.checkboxButton.state = MacLCConfigGetInt("macosx-lock-aspect-ratio", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    char *snapPath = MacLCConfigGetPsz("snapshot-path");
    _snapFolderRow.textField.stringValue = snapPath ? toNSStr(snapPath) : @"";
    free(snapPath);

    char *snapPrefix = MacLCConfigGetPsz("snapshot-prefix");
    _snapPrefixRow.textField.stringValue = snapPrefix ? toNSStr(snapPrefix) : @"maclcsnap-";
    free(snapPrefix);

    char *snapFormat = MacLCConfigGetPsz("snapshot-format");
    NSString *fmtStr = snapFormat ? toNSStr(snapFormat) : @"png";
    free(snapFormat);
    [_snapFormatRow.popUpButton selectItemWithTitle:fmtStr];

    _snapSequentialRow.checkboxButton.state = MacLCConfigGetInt("snapshot-sequential", 0) ? NSControlStateValueOn : NSControlStateValueOff;

    self.hasUnsavedChanges = NO;
}

- (void)applyChanges
{
    MacLCConfigPutInt("video", _videoEnableRow.checkboxButton.state == NSControlStateValueOn);
    /* A display saved then unplugged matches no item: keep it saved rather
     * than writing the -1 of an empty selection. */
    if (_targetScreenRow.popUpButton.selectedTag >= 0)
        MacLCConfigPutInt("macosx-vdev", _targetScreenRow.popUpButton.selectedTag);
    MacLCConfigPutInt("video-on-top", _onTopRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-video-autoresize", _autoResizeRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-pause-minimized", _pauseMinimizedRow.checkboxButton.state == NSControlStateValueOn);

    MacLCConfigPutInt("fullscreen", _startFullscreenRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-nativefullscreenmode", _nativeFullscreenRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-black", _blackScreenRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutInt("macosx-dim-keyboard", _dimKeyboardRow.checkboxButton.state == NSControlStateValueOn);

    MacLCConfigPutInt("deinterlace", _deinterlaceRow.popUpButton.selectedTag);

    NSArray *modes = @[@"auto", @"discard", @"blend", @"bob", @"linear", @"yadif", @"yadif2x"];
    NSInteger mIdx = _deinterlaceModeRow.popUpButton.indexOfSelectedItem;
    if (mIdx >= 0 && mIdx < (NSInteger)modes.count) {
        MacLCConfigPutPsz("deinterlace-mode", [modes[mIdx] UTF8String]);
    }

    /* The filter reads every one of these once, when it opens, so they are
     * written before the engine is set -- setting the engine restarts a
     * running filter, and it should restart onto the new values. */
    MacLCConfigPutInt("maclc-frc-overrun", _interpolationOverrunRow.popUpButton.selectedTag);
    MacLCConfigPutInt("maclc-frc-rife",
                      _interpolationRifeRow.checkboxButton.state == NSControlStateValueOn);
    MacLCConfigPutFloat("maclc-frc-rife-scale",
                        (float)_interpolationRifeScaleRow.popUpButton.selectedTag / 100.0f);
    MacLCConfigPutPsz("maclc-frc-rife-model",
                      [_interpolationRifeModelRow.textField.stringValue UTF8String]);
    MacLCConfigPutPsz("maclc-frc-svp-path",
                      [_interpolationSvpPathRow.textField.stringValue UTF8String]);

    const NSInteger engine = _interpolationRow.popUpButton.selectedTag;
    if (engine >= 0)
        MacLCFrameInterpolation.engine = (MacLCFrameInterpolationEngine)engine;
    MacLCFrameInterpolation.target =
        (MacLCFrameInterpolationTarget)_interpolationTargetRow.popUpButton.selectedTag;
    [MacLCFrameInterpolation setEnabled:engine >= 0];
    /* Nothing above restarts the filter when the engine and the target were
     * already what they are and only a sub-option moved. */
    [MacLCFrameInterpolation restartIfRunning];

    NSString *aspectTitle = _aspectRatioRow.popUpButton.titleOfSelectedItem;
    if ([aspectTitle isEqualToString:_NS("Default")]) {
        MacLCConfigPutPsz("aspect-ratio", "");
    } else {
        MacLCConfigPutPsz("aspect-ratio", [aspectTitle UTF8String]);
    }

    NSString *cropTitle = _cropRatioRow.popUpButton.titleOfSelectedItem;
    if ([cropTitle isEqualToString:_NS("Default")]) {
        MacLCConfigPutPsz("crop", "");
    } else {
        MacLCConfigPutPsz("crop", [cropTitle UTF8String]);
    }

    MacLCConfigPutInt("macosx-lock-aspect-ratio", _lockAspectRow.checkboxButton.state == NSControlStateValueOn);

    MacLCConfigPutPsz("snapshot-path", [_snapFolderRow.textField.stringValue UTF8String]);
    MacLCConfigPutPsz("snapshot-prefix", [_snapPrefixRow.textField.stringValue UTF8String]);
    MacLCConfigPutPsz("snapshot-format", [_snapFormatRow.popUpButton.titleOfSelectedItem UTF8String]);
    MacLCConfigPutInt("snapshot-sequential", _snapSequentialRow.checkboxButton.state == NSControlStateValueOn);

    self.hasUnsavedChanges = NO;
}

- (void)resetToDefaults
{
    module_config_t *item;
    if ((item = config_FindConfig("video"))) MacLCConfigPutInt("video", item->orig.i);
    if ((item = config_FindConfig("macosx-vdev"))) MacLCConfigPutInt("macosx-vdev", item->orig.i);
    if ((item = config_FindConfig("video-on-top"))) MacLCConfigPutInt("video-on-top", item->orig.i);
    if ((item = config_FindConfig("macosx-video-autoresize"))) MacLCConfigPutInt("macosx-video-autoresize", item->orig.i);
    if ((item = config_FindConfig("macosx-pause-minimized"))) MacLCConfigPutInt("macosx-pause-minimized", item->orig.i);
    if ((item = config_FindConfig("fullscreen"))) MacLCConfigPutInt("fullscreen", item->orig.i);
    if ((item = config_FindConfig("macosx-nativefullscreenmode"))) MacLCConfigPutInt("macosx-nativefullscreenmode", item->orig.i);
    if ((item = config_FindConfig("macosx-black"))) MacLCConfigPutInt("macosx-black", item->orig.i);
    if ((item = config_FindConfig("macosx-dim-keyboard"))) MacLCConfigPutInt("macosx-dim-keyboard", item->orig.i);
    if ((item = config_FindConfig("deinterlace"))) MacLCConfigPutInt("deinterlace", item->orig.i);
    if ((item = config_FindConfig("deinterlace-mode"))) MacLCConfigPutPsz("deinterlace-mode", item->orig.psz ? item->orig.psz : "auto");
    if ((item = config_FindConfig("aspect-ratio"))) MacLCConfigPutPsz("aspect-ratio", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("crop"))) MacLCConfigPutPsz("crop", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("macosx-lock-aspect-ratio"))) MacLCConfigPutInt("macosx-lock-aspect-ratio", item->orig.i);
    [MacLCFrameInterpolation setEnabled:NO];
    if ((item = config_FindConfig("maclc-frc-engine"))) MacLCConfigPutInt("maclc-frc-engine", item->orig.i);
    if ((item = config_FindConfig("maclc-frc-target"))) MacLCConfigPutInt("maclc-frc-target", item->orig.i);
    if ((item = config_FindConfig("maclc-frc-overrun"))) MacLCConfigPutInt("maclc-frc-overrun", item->orig.i);
    if ((item = config_FindConfig("maclc-frc-rife"))) MacLCConfigPutInt("maclc-frc-rife", item->orig.i);
    if ((item = config_FindConfig("maclc-frc-rife-scale"))) MacLCConfigPutFloat("maclc-frc-rife-scale", item->orig.f);
    if ((item = config_FindConfig("maclc-frc-rife-model"))) MacLCConfigPutPsz("maclc-frc-rife-model", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("maclc-frc-svp-path"))) MacLCConfigPutPsz("maclc-frc-svp-path", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("snapshot-path"))) MacLCConfigPutPsz("snapshot-path", item->orig.psz ? item->orig.psz : "");
    if ((item = config_FindConfig("snapshot-prefix"))) MacLCConfigPutPsz("snapshot-prefix", item->orig.psz ? item->orig.psz : "maclcsnap-");
    if ((item = config_FindConfig("snapshot-format"))) MacLCConfigPutPsz("snapshot-format", item->orig.psz ? item->orig.psz : "png");
    if ((item = config_FindConfig("snapshot-sequential"))) MacLCConfigPutInt("snapshot-sequential", item->orig.i);

    [self loadSettings];
    self.hasUnsavedChanges = YES;
}

@end
