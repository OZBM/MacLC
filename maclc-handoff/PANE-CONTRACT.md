# MacLC — settings pane contract

Several agents build settings panes in parallel. They agree on this contract so
the pieces fit together without any of them seeing the others' code.

The settings window owns a list of panes. A pane is a plain `NSViewController`
subclass that also implements the following. Copy these declarations verbatim.

```objc
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
```

## Rules every pane follows

- The designated initialiser is `- (instancetype)initWithIntf:(intf_thread_t *)intf`.
  Keep the `intf_thread_t *` for `config_Get*` / `config_Put*` calls.
- A pane never calls `config_SaveConfigFile()`. The window does that once.
- A pane builds its UI programmatically with Auto Layout. No new XIBs.
- A pane's root view must lay out correctly at any width from 480 pt upward and
  size its own height from its content, so the window can scroll it.
- Every user-visible string goes through `_NS()`, and the pane's source file is
  added to `po/POTFILES.in`.
- Every control has an accessibility label; every explanation label is
  `NSAccessibilityStaticText` and associated with its control.

## The row idiom

Panes are built from titled cards; each card holds rows. A row is:

```
┌──────────────────────────────────────────────────────────────────┐
│ Label text                                        [ control ]    │
│ One sentence saying what changing this does, in terms of what    │
│ the user will see or hear.                                       │
└──────────────────────────────────────────────────────────────────┘
```

- Label: `.body`, primary label colour.
- Explanation: `.caption1` (or `.footnote`), secondary label colour, wraps to as
  many lines as it needs, never truncated.
- Control: trailing-aligned, vertically centred on the label line.
- A row that is risky gets a warning symbol (`exclamationmark.triangle.fill`,
  warning colour) before its label, and its explanation states the concrete
  failure ("playback stops and you get a black screen").
- A row whose value differs from the built-in default shows a small
  "Default: <value>" hint or a reset affordance.
