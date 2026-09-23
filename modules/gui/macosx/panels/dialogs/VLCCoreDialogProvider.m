/*****************************************************************************
 * VLCCoreDialogProvider.m: Mac OS X Core Dialogs
 *****************************************************************************
 * Copyright (C) 2005-2019 VLC authors and VideoLAN
 *
 * Authors: Derk-Jan Hartman <hartman at videolan dot org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
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

#import "VLCCoreDialogProvider.h"

#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "windows/VLCErrorWindowController.h"

#import <vlc_common.h>
#import <vlc_dialog.h>

@interface VLCCoreDialogProvider ()
{
    VLCErrorWindowController *_errorPanel;
    /* The progress dialog on screen, and those waiting for the window. The
     * provider holds a reference on each until it calls
     * vlc_dialog_id_dismiss(), which also means "cancelled": a dialog is
     * only dismissed when the user cancels it or the core releases it. */
    vlc_dialog_id *_progressDialogID;
    vlc_dialog_id *_modalDialogID; /* login or question alert running */
    NSMutableArray<NSDictionary *> *_pendingProgressDialogs;
}

- (void)cancelDialog:(vlc_dialog_id *)dialogID;

- (void)displayErrorWithTitle:(NSString *)title
                         text:(NSString *)text;

- (void)displayLoginDialog:(vlc_dialog_id *)dialogID
                     title:(NSString *)title
                      text:(NSString *)text
                  username:(NSString *)username
                askToStore:(BOOL)askToStore;

- (void)displayQuestion:(vlc_dialog_id *)dialogID
                  title:(NSString *)title
                   text:(NSString *)text
                   type:(vlc_dialog_question_type)questionType
             cancelText:(NSString *)cancelText
            action1Text:(NSString *)action1Text
            action2Text:(NSString *)action2Text;

- (void)displayProgressDialog:(vlc_dialog_id *)dialogID
                        title:(NSString *)title
                         text:(NSString *)text
                indeterminate:(BOOL)indeterminate
                     position:(float)position
                  cancelTitle:(NSString *)cancelTitle;

- (void)updateDisplayedProgressDialog:(vlc_dialog_id *)dialogID
                             position:(float)position
                                 text:(NSString *)text;

@end

static void displayErrorCallback(void *p_data,
                                 const char *psz_title,
                                 const char *psz_text)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        NSString *title = VLCSubstituteBrandNames(toNSStr(psz_title));
        NSString *text = VLCSubstituteBrandNames(toNSStr(psz_text));
        dispatch_async(dispatch_get_main_queue(), ^{
            [dialogProvider displayErrorWithTitle:title text:text];
        });
    }
}

static void displayLoginCallback(void *p_data,
                                 vlc_dialog_id *p_id,
                                 const char *psz_title,
                                 const char *psz_text,
                                 const char *psz_default_username,
                                 bool b_ask_store)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        NSString *title = VLCSubstituteBrandNames(toNSStr(psz_title));
        NSString *text = VLCSubstituteBrandNames(toNSStr(psz_text));
        NSString *defaultUsername = toNSStr(psz_default_username);
        dispatch_async(dispatch_get_main_queue(), ^{
            [dialogProvider displayLoginDialog:p_id
                                         title:title
                                          text:text
                                      username:defaultUsername
                                    askToStore:b_ask_store];
        });
    }
}

static void displayQuestionCallback(void *p_data,
                                    vlc_dialog_id *p_id,
                                    const char *psz_title,
                                    const char *psz_text,
                                    vlc_dialog_question_type i_type,
                                    const char *psz_cancel,
                                    const char *psz_action1,
                                    const char *psz_action2)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge  VLCCoreDialogProvider *)p_data;
        NSString *title = VLCSubstituteBrandNames(toNSStr(psz_title));
        NSString *text = VLCSubstituteBrandNames(toNSStr(psz_text));
        NSString *cancelText = VLCSubstituteBrandNames(toNSStr(psz_cancel));
        NSString *action1Text = VLCSubstituteBrandNames(toNSStr(psz_action1));
        NSString *action2Text = VLCSubstituteBrandNames(toNSStr(psz_action2));
        dispatch_async(dispatch_get_main_queue(), ^{
            [dialogProvider displayQuestion:p_id
                                      title:title
                                       text:text
                                       type:i_type
                                 cancelText:cancelText
                                action1Text:action1Text
                                action2Text:action2Text];
        });
    }
}

static void displayProgressCallback(void *p_data,
                                    vlc_dialog_id *p_id,
                                    const char *psz_title,
                                    const char *psz_text,
                                    bool b_indeterminate,
                                    float f_position,
                                    const char *psz_cancel)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        dispatch_async(dispatch_get_main_queue(), ^{
            [dialogProvider displayProgressDialog:p_id
                                            title:VLCSubstituteBrandNames(toNSStr(psz_title))
                                             text:VLCSubstituteBrandNames(toNSStr(psz_text))
                                    indeterminate:b_indeterminate
                                         position:f_position
                                      cancelTitle:VLCSubstituteBrandNames(toNSStr(psz_cancel))];
        });
    }
}

static void cancelCallback(void *p_data,
                           vlc_dialog_id *p_id)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        dispatch_async(dispatch_get_main_queue(), ^{
            [dialogProvider cancelDialog:p_id];
        });
    }
}

static void updateProgressCallback(void *p_data,
                                   vlc_dialog_id *p_id,
                                   float f_value,
                                   const char *psz_text)
{
    @autoreleasepool {
        VLCCoreDialogProvider *dialogProvider = (__bridge VLCCoreDialogProvider *)p_data;
        /* The text belongs to the caller: copy it before leaving. AppKit
         * views: main thread only. */
        NSString * const text = VLCSubstituteBrandNames(toNSStr(psz_text));
        dispatch_async(dispatch_get_main_queue(), ^{
            [dialogProvider updateDisplayedProgressDialog:p_id
                                                 position:f_value
                                                     text:text];
        });
    }
}

@implementation VLCCoreDialogProvider

- (instancetype)init
{
    self = [super init];

    if (self) {
        msg_Dbg(getIntf(), "Register dialog provider");
        [[NSBundle mainBundle] loadNibNamed:@"CoreDialogs" owner:self topLevelObjects:nil];

        intf_thread_t *p_intf = getIntf();
        /* subscribe to various interactive dialogues */

        const vlc_dialog_cbs cbs = {
            displayLoginCallback,
            displayQuestionCallback,
            displayProgressCallback,
            cancelCallback,
            updateProgressCallback
        };

        vlc_dialog_provider_set_error_callback(p_intf, displayErrorCallback, (__bridge void *)self);
        vlc_dialog_provider_set_callbacks(p_intf, &cbs, (__bridge void *)self);
    }

    return self;
}

- (void)dealloc
{
    /* This object can outlive the interface, in which case there is no
     * provider left to unregister from. */
    intf_thread_t * const p_intf = getIntf();
    if (p_intf == NULL) {
        return;
    }

    msg_Dbg(p_intf, "Deinitializing dialog provider");

    vlc_dialog_provider_set_callbacks(p_intf, NULL, NULL);
    vlc_dialog_provider_set_error_callback(p_intf, NULL, NULL);
}

-(void)awakeFromNib
{
    [_authenticationLoginLabel setStringValue: _NS("Username")];
    [_authenticationPasswordLabel setStringValue: _NS("Password")];
    [_authenticationCancelButton setTitle: _NS("Cancel")];
    [_authenticationOkButton setTitle: _NS("OK")];
    [_authenticationStorePasswordCheckbox setTitle:_NS("Remember")];

    [_progressCancelButton setTitle: _NS("Cancel")];
    [_progressIndicator setUsesThreadedAnimation: YES];
}

- (void)displayErrorWithTitle:(NSString *)title text:(NSString *)text
{
    if (!_errorPanel) {
        _errorPanel = [[VLCErrorWindowController alloc] init];
    }
    [_errorPanel showWindow:nil];
    [_errorPanel addError:title withMsg:text];
}

- (void)displayLoginDialog:(vlc_dialog_id *)dialogID
                     title:(NSString *)title
                      text:(NSString *)text
                  username:(NSString *)username
                askToStore:(BOOL)askToStore
{
    [_authenticationTitleLabel setStringValue:title];
    _authenticationWindow.title = title;
    [_authenticationDescriptionLabel setStringValue:text];

    [_authenticationLoginTextField setStringValue:username];
    [_authenticationPasswordTextField setStringValue:@""];

    _authenticationStorePasswordCheckbox.hidden = !askToStore;
    _authenticationStorePasswordCheckbox.state = NSOffState;

    [_authenticationWindow center];
    _modalDialogID = dialogID;
    NSInteger returnValue = [NSApp runModalForWindow:_authenticationWindow];
    _modalDialogID = NULL;
    [_authenticationWindow close];

    username = _authenticationLoginTextField.stringValue;
    NSString *password = _authenticationPasswordTextField.stringValue;
    if (returnValue == 0) {
        vlc_dialog_id_dismiss(dialogID);
    } else {
        vlc_dialog_id_post_login(dialogID,
                                 username ? [username UTF8String] : NULL,
                                 password ? [password UTF8String] : NULL,
                                 _authenticationStorePasswordCheckbox.state == NSOnState);
    }
}

- (IBAction)authenticationDialogAction:(id)sender
{
    if ([[sender title] isEqualToString: _NS("OK")])
        [NSApp stopModalWithCode: 1];
    else
        [NSApp stopModalWithCode: 0];
}

- (void)displayQuestion:(vlc_dialog_id *)dialogID
                  title:(NSString *)title
                   text:(NSString *)text
                   type:(vlc_dialog_question_type)questionType
             cancelText:(NSString *)cancelText
            action1Text:(NSString *)action1Text
            action2Text:(NSString *)action2Text
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:title];
    [alert setInformativeText:text];
    [alert addButtonWithTitle:action1Text];
    [alert addButtonWithTitle:action2Text];
    [alert addButtonWithTitle:cancelText];
    [alert.buttons.lastObject setKeyEquivalent:[NSString stringWithFormat:@"%C", 0x1b]];

    switch (questionType) {
        case VLC_DIALOG_QUESTION_WARNING:
            [alert setAlertStyle:NSAlertStyleWarning];
            break;
        case VLC_DIALOG_QUESTION_CRITICAL:
            [alert setAlertStyle:NSAlertStyleCritical];
            break;
        default:
            [alert setAlertStyle:NSAlertStyleInformational];
            break;
    }

    _modalDialogID = dialogID;
    NSInteger returnValue = [alert runModal];
    _modalDialogID = NULL;
    switch (returnValue) {
        case NSAlertFirstButtonReturn:
            vlc_dialog_id_post_action(dialogID, 1);
            break;

        case NSAlertSecondButtonReturn:
            vlc_dialog_id_post_action(dialogID, 2);
            break;

        case NSAlertThirdButtonReturn:
        default:
            vlc_dialog_id_dismiss(dialogID);
    }

}

- (void)displayProgressDialog:(vlc_dialog_id *)dialogID
                        title:(NSString *)title
                         text:(NSString *)text
                indeterminate:(BOOL)indeterminate
                     position:(float)position
                  cancelTitle:(NSString *)cancelTitle
{
    /* One window: a second dialog waits for the first to go. */
    if (_progressDialogID != NULL && _progressDialogID != dialogID) {
        if (_pendingProgressDialogs == nil) {
            _pendingProgressDialogs = [NSMutableArray array];
        }
        [_pendingProgressDialogs addObject:@{
            @"id": [NSValue valueWithPointer:dialogID],
            @"title": title ?: @"",
            @"text": text ?: @"",
            @"indeterminate": @(indeterminate),
            @"position": @(position),
            @"cancel": cancelTitle ?: @"",
        }];
        return;
    }
    _progressTitleLabel.stringValue = title;
    _progressWindow.title = title;

    _progressDescriptionLabel.stringValue = text;

    _progressIndicator.indeterminate = indeterminate;
    _progressIndicator.doubleValue = position;

    if ([cancelTitle length] > 0) {
        _progressCancelButton.title = cancelTitle;
        _progressCancelButton.enabled = YES;
    } else {
        _progressCancelButton.title = _NS("Cancel");
        _progressCancelButton.enabled = NO;
    }

    _progressDialogID = dialogID;

    [_progressIndicator startAnimation:self];

    /* Not modal: this runs in a block on the main queue, and a modal loop
     * here kept that queue busy for as long as the dialog stayed up, so
     * everything the core sends to the main thread synchronously waited
     * behind it - creating a video window among them, which froze
     * playback and quitting. */
    if (!_progressWindow.visible) {
        [_progressWindow center];
    }
    [_progressWindow orderFront:self];
}

- (NSUInteger)indexOfPendingProgressDialog:(vlc_dialog_id *)dialogID
{
    return [_pendingProgressDialogs indexOfObjectPassingTest:^BOOL(NSDictionary * const entry, NSUInteger __unused idx, BOOL * __unused stop) {
        return [entry[@"id"] pointerValue] == dialogID;
    }];
}

- (void)closeProgressDialog
{
    vlc_dialog_id * const dialogID = _progressDialogID;
    if (dialogID == NULL) {
        return;
    }
    _progressDialogID = NULL;
    [_progressIndicator stopAnimation:self];
    [_progressWindow orderOut:self];
    vlc_dialog_id_dismiss(dialogID);

    if (_pendingProgressDialogs.count > 0) {
        NSDictionary * const next = _pendingProgressDialogs.firstObject;
        [_pendingProgressDialogs removeObjectAtIndex:0];
        [self displayProgressDialog:[next[@"id"] pointerValue]
                              title:next[@"title"]
                               text:next[@"text"]
                      indeterminate:[next[@"indeterminate"] boolValue]
                           position:[next[@"position"] floatValue]
                        cancelTitle:next[@"cancel"]];
    }
}

- (void)cancelDialog:(vlc_dialog_id *)dialogID
{
    if (dialogID == _progressDialogID) {
        [self closeProgressDialog];
        return;
    }
    const NSUInteger pending = [self indexOfPendingProgressDialog:dialogID];
    if (pending != NSNotFound) {
        [_pendingProgressDialogs removeObjectAtIndex:pending];
        vlc_dialog_id_dismiss(dialogID);
        return;
    }
    /* Login and question dialogs are still modal alerts. Another id is a
     * progress dialog closed meanwhile: stopping the modal session then
     * would end someone else's (an open panel). */
    if (dialogID == _modalDialogID) {
        [NSApp stopModalWithCode:0];
    }
}

- (void)updateDisplayedProgressDialog:(vlc_dialog_id *)dialogID
                             position:(float)position
                                 text:(NSString *)text
{
    if (dialogID != _progressDialogID) {
        const NSUInteger pending = [self indexOfPendingProgressDialog:dialogID];
        if (pending != NSNotFound) {
            NSMutableDictionary * const entry = [_pendingProgressDialogs[pending] mutableCopy];
            if (text.length > 0)
                entry[@"text"] = text;
            entry[@"position"] = @(position);
            _pendingProgressDialogs[pending] = entry;
        }
        return; /* waiting for the window, or dismissed meanwhile */
    }
    if (!_progressIndicator.indeterminate) {
        _progressIndicator.doubleValue = position;
    }
    if (text.length > 0) {
        _progressDescriptionLabel.stringValue = text;
    }
}

- (VLCErrorWindowController *)errorPanel
{
    if (!_errorPanel) {
        _errorPanel = [[VLCErrorWindowController alloc] init];
    }

    return _errorPanel;
}

- (IBAction)progressDialogAction:(id)sender
{
    [self closeProgressDialog];
}

@end
