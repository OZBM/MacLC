/*****************************************************************************
 * MacLCExplainer.h: plain-language explanations of the words Watch uses
 * (peers, Dolby Vision, Remux...), shown as a tip when the pointer rests on
 * them
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* Design (offering-help.md, popovers.md). The explanation is a popover tip
 * (offering-help.md › Creating tips: "Display a popover tip when you want to
 * preserve the content flow"; one or two sentences; the feature's filled
 * symbol). One deliberate departure: it opens when the pointer RESTS on the
 * word for 0.6 s, as a help tag does (offering-help.md › Desktop: "tooltips
 * can appear when a person holds the pointer over an element"), where
 * popovers.md says popovers appear "when people click". Why: the people
 * these tips are for do not know there is anything to click on a word such
 * as "Peers"; a plain help tag (60-75 characters, no picture) cannot explain
 * a torrent to a newcomer. The same tip also opens on click, on Space or
 * Return when the word has keyboard focus, and VoiceOver reads it as the
 * element's help, so it never depends on hovering.
 *
 * Look: an NSPopover (behavior transient, appearance of the window), 300 pt
 * wide: a 28 pt filled SF Symbol in the topic's tint inside a 44 pt circle of
 * that tint at 15 %, the title (headline), one or two sentences (body,
 * secondaryLabel, wrapping), and, when the topic has one, a "What this means
 * for you" line (callout, labelColor) such as "More people = starts faster
 * and doesn't pause." Some topics show a small live illustration under the
 * text (see MacLCExplainerIllustration). Motion: NSPopover's own animation;
 * the illustration animates only without Reduce Motion (static frame
 * otherwise). It closes when the pointer leaves both the word and the tip
 * (0.25 s grace), on Escape, or on click elsewhere. One tip at a time
 * (popovers.md › "Show one popover at a time"). */
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Every word explained. Text lives in MacLCExplainer.m only.
typedef NSString *MacLCExplainerTopic NS_TYPED_EXTENSIBLE_ENUM;
/* Torrents */
extern MacLCExplainerTopic const MacLCExplainerTopicPeers;        /* the people sharing (👤) */
extern MacLCExplainerTopic const MacLCExplainerTopicHealth;       /* the connection meter */
extern MacLCExplainerTopic const MacLCExplainerTopicTorrent;      /* what a torrent is */
extern MacLCExplainerTopic const MacLCExplainerTopicDebrid;       /* [RD+] cached */
extern MacLCExplainerTopic const MacLCExplainerTopicSize;         /* file size, data use */
extern MacLCExplainerTopic const MacLCExplainerTopicPack;         /* season pack / collection */
extern MacLCExplainerTopic const MacLCExplainerTopicProvider;     /* ⚙️ the site it was found on */
/* Picture */
extern MacLCExplainerTopic const MacLCExplainerTopicResolution4K;
extern MacLCExplainerTopic const MacLCExplainerTopicResolution1080p;
extern MacLCExplainerTopic const MacLCExplainerTopicResolution720p;
extern MacLCExplainerTopic const MacLCExplainerTopicDolbyVision;
extern MacLCExplainerTopic const MacLCExplainerTopicHDR10Plus;
extern MacLCExplainerTopic const MacLCExplainerTopicHDR10;        /* also "HDR" */
extern MacLCExplainerTopic const MacLCExplainerTopicHLG;
extern MacLCExplainerTopic const MacLCExplainerTopicSDR;
extern MacLCExplainerTopic const MacLCExplainerTopicHEVC;         /* and AV1, H.264: "codec" */
extern MacLCExplainerTopic const MacLCExplainerTopicUpscaled;
/* Source */
extern MacLCExplainerTopic const MacLCExplainerTopicRemux;
extern MacLCExplainerTopic const MacLCExplainerTopicBluRay;
extern MacLCExplainerTopic const MacLCExplainerTopicWebDL;
extern MacLCExplainerTopic const MacLCExplainerTopicWebRip;
extern MacLCExplainerTopic const MacLCExplainerTopicCam;          /* CAM, TS, screener */
/* Sound and language */
extern MacLCExplainerTopic const MacLCExplainerTopicAtmos;        /* and DTS:X */
extern MacLCExplainerTopic const MacLCExplainerTopicLosslessAudio;/* TrueHD, DTS-HD MA, FLAC, PCM */
extern MacLCExplainerTopic const MacLCExplainerTopicSurround;     /* 5.1, 7.1 */
extern MacLCExplainerTopic const MacLCExplainerTopicMultiAudio;
extern MacLCExplainerTopic const MacLCExplainerTopicSubtitles;
/* Discovery */
extern MacLCExplainerTopic const MacLCExplainerTopicAddons;       /* where titles and streams come from */
extern MacLCExplainerTopic const MacLCExplainerTopicServices;     /* the services filter */
extern MacLCExplainerTopic const MacLCExplainerTopicCollections;  /* The Edit, renewed every two weeks */
extern MacLCExplainerTopic const MacLCExplainerTopicBestMatch;    /* how the best version is chosen */
extern MacLCExplainerTopic const MacLCExplainerTopicVerdict;      /* Great / Good / Okay / Poor */

/// What a tip may draw under its text.
typedef NS_ENUM(NSInteger, MacLCExplainerIllustration) {
    MacLCExplainerIllustrationNone = 0,
    /// Peers: a central Mac (laptopcomputer) with 6 small person.fill dots
    /// around it; pieces (small accent squares) travel from each dot to the
    /// Mac in turn, 1.2 s loop. Caption-free.
    MacLCExplainerIllustrationPeers,
    /// Health: the 4-bar meter filling 1→4 bars, labels "Few" ... "Many".
    MacLCExplainerIllustrationHealth,
    /// Dynamic range: a gradient bar from black to white, SDR stopping at
    /// "100 nits", HDR running brighter (white → extra-bright with a glow).
    MacLCExplainerIllustrationDynamicRange,
    /// Resolution: nested rectangles 720p ⊂ 1080p ⊂ 4K drawn to scale.
    MacLCExplainerIllustrationResolution,
    /// Surround / Atmos: a top view of a couch with speaker dots around
    /// (and above, for Atmos), pulsing in turn.
    MacLCExplainerIllustrationSurround,
};

@interface MacLCExplainer : NSObject

/// The title, e.g. "Peers".
+ (NSString *)titleForTopic:(MacLCExplainerTopic)topic;
/// One or two plain sentences for someone who has never heard the word,
/// e.g. Peers: "People who have this video on their computer and are
/// sending pieces of it to you right now. You get the video from many of
/// them at once."
+ (NSString *)explanationForTopic:(MacLCExplainerTopic)topic;
/// "What this means for you", or nil, e.g. Peers: "More people means the
/// video starts sooner and doesn't pause. Under 5 can be slow."
+ (nullable NSString *)consequenceForTopic:(MacLCExplainerTopic)topic;
/// Filled SF Symbol name, e.g. "person.2.fill".
+ (NSString *)symbolNameForTopic:(MacLCExplainerTopic)topic;
+ (NSColor *)tintForTopic:(MacLCExplainerTopic)topic;
+ (MacLCExplainerIllustration)illustrationForTopic:(MacLCExplainerTopic)topic;

/// Makes view explain topic: rests 0.6 s → tip; click on it (when it is not
/// a control with its own action), Space or Return while focused → tip;
/// sets view.accessibilityHelp to the explanation (+ consequence) and, for
/// VoiceOver, adds the custom action "Explain". Calling it again replaces
/// the topic; nil topic removes it all. The view need not be a control;
/// a plain label works (it gets a tracking area). Does not change its look:
/// callers add the dotted underline or the ⓘ themselves when they want one.
+ (void)attachToView:(NSView *)view topic:(nullable MacLCExplainerTopic)topic;

/// Shows the tip for topic now, pointing at view (preferred edge max-Y).
+ (void)showTopic:(MacLCExplainerTopic)topic relativeToView:(NSView *)view;
/// Closes the tip shown, if any.
+ (void)dismiss;

/// A small borderless "info.circle" button (16 pt symbol, secondaryLabel,
/// accent on hover, 22 × 22 hit area) that opens the tip on click and on
/// hover; accessibility label "Explain <title>".
+ (NSButton *)infoButtonForTopic:(MacLCExplainerTopic)topic;

/// A label whose text is underlined with a dotted line in tertiaryLabel
/// (NSUnderlineStylePatternDot | NSUnderlineStyleSingle) — the web's and
/// Pages' convention for "there is an explanation here" — already attached.
+ (NSTextField *)explainedLabelWithString:(NSString *)string
                                     font:(NSFont *)font
                                    color:(NSColor *)color
                                    topic:(MacLCExplainerTopic)topic;

@end

NS_ASSUME_NONNULL_END
