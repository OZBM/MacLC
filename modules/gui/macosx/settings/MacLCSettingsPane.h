/**
 * A single page of MacLC settings.
 *
 * The settings window instantiates one view controller per pane, shows its
 * -view inside a scroll view, and drives it through the methods below. A pane
 * owns its own layout, reads and writes VLC config options itself, and never
 * assumes anything about its container beyond the width it is given.
 */
@protocol MacLCSettingsPane <NSObject>

/// Localised title shown in the settings sidebar and as the pane heading.
@property (readonly, nonatomic) NSString *paneTitle;

/// SF Symbol name for the sidebar row. Must exist on macOS 13.
@property (readonly, nonatomic) NSString *paneSymbolName;

/// A stable, non-localised identifier, e.g. @"video-hdr".
@property (readonly, nonatomic) NSString *paneIdentifier;

/// Lowercased words the settings search field matches against, including the
/// localised labels and explanations of every control this pane shows, plus
/// the raw VLC option names so power users can search for them.
@property (readonly, nonatomic) NSArray<NSString *> *searchKeywords;

/// Read every value this pane displays out of the VLC configuration and update
/// the controls. Called before the pane is first shown and whenever the
/// settings window is reopened. Must be safe to call repeatedly.
- (void)loadSettings;

/// Write every changed value back with config_Put*(). The window calls
/// config_SaveConfigFile() once afterwards, so panes must NOT save themselves.
- (void)applyChanges;

/// Restore every option this pane owns to its built-in default and refresh the
/// controls. Backs the per-section "Reset" button.
- (void)resetToDefaults;

@optional

/// YES while the pane has edits that -applyChanges would write. Lets the window
/// enable/disable its Apply button. Panes that apply instantly return NO.
@property (readonly, nonatomic) BOOL hasUnsavedChanges;

/// Called when the pane becomes visible / hidden, so a pane that observes live
/// state (playback, display changes) can start and stop watching.
- (void)paneDidAppear;
- (void)paneDidDisappear;

@end
