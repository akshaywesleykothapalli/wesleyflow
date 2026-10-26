# Browser accessibility activation — declined proposal

Status: NOT IMPLEMENTED / USER DECLINED. On 2026-10-20 the user explicitly selected “No, keep this change disabled” after the exact foreground-app attribute change and risks were presented. Both attempted edit commands were rejected before execution; neither added activation code. Automatic approval review rejected an attempted source-edit command before it executed because the proposed activation changes accessibility behavior in other foreground apps without explicit user authorization for that exact change. No activation code was added, no third-party accessibility attribute was written and no alternate tool was used to bypass the rejection.

## Evidence and current scope

The user confirms hold-Fn capture and insertion in System Settings/system apps, but failure in WhatsApp and browser editors. Wesley Flow's own status identifies a missing focused text field before insertion. Automated Codex inspection is prohibited by the UI tool; that separate restriction remains respected.

The implemented correction is only read-only focus lookup: application focus first, then Apple system-wide focus when absent, with AXUIElementGetPid matching the original captured process before reading any field value. Foreign, absent or unidentifiable owners fail closed. All original window/launch/element/selection/text/permission/secure-field checks remain. No browser DOM, blind paste or permission bypass is used.

Apple documents system-wide focus discovery: https://developer.apple.com/documentation/applicationservices/1462095-axuielementcreatesystemwide

## Proposed activation, requiring explicit approval

Wesley Flow would request that the user-selected foreground app expose its accessibility tree while authorized hold-Fn mode is enabled. For Electron, prefer its supported AXManualAccessibility capability; Chromium may require AXEnhancedUserInterface. Request only advertised/settable Boolean attributes, only with existing macOS Accessibility consent, and only on the same current PID/launch identity after revalidation. Read only app-role/support metadata during preparation, not messages or field contents. A bounded identity cache prevents repeated activation requests; entering a dictation still binds/revalidates the actual target and preserves all insertion checks. No new OS permission, browser flag, extension, command, restart, VoiceOver toggle or system preference change would be performed.

Activation can build a larger browser accessibility tree and affect performance/memory. Enhanced mode can change screen-reader-related behavior inside the target app. Some versions debounce activation for about two seconds, so the tree may not be available instantly. App support varies; no universal typing guarantee follows. Do not disable accessibility later because another accessibility client may depend on it; it may remain enabled in that app until the app exits. This is why the exact cross-application behavior needs review/approval.

Primary sources consulted, 2026-10-20:
- Chromium documentation: https://www.chromium.org/developers/design-documents/accessibility/
- Chromium implementation: https://chromium.googlesource.com/chromium/src/+/master/chrome/browser/chrome_browser_application_mac.mm
- Electron implementation (attribute contract and delayed activation): https://raw.githubusercontent.com/electron/electron/main/shell/browser/mac/electron_application.mm

These are general upstream sources, not version-pinned conformance evidence for the installed WhatsApp, browser or Codex application. No source was copied into Wesley Flow. The proposal remains blocked until the user explicitly authorizes requesting accessibility-tree activation in other foreground apps.
