# Android Cupertino hardware evidence

These files record selected physical-device UI checks on September 21, 2026.
They do not establish all-surface coverage. Final two-phone pairing and joint
genesis and independent sign-in passed in the separate
[protocol evidence](../../phone-v2-hardware/README.md). Current build details are in
[`../android-apk-build.json`](../android-apk-build.json).

## Build boundaries

| Files | Build and scope |
| --- | --- |
| `../android-install.json`, `../android-launch.json` | Initial `4ca2c9a` Pixel install and cold launch. Both legacy files matched before/after this install; the phone was locked at that checkpoint. |
| PNG/XML files directly in this directory | Earlier Pixel exploratory smoke, including the failures below. Names such as `alert-open`, `text-fast-appended` and `sheet-closed` are observations, not passing-result labels. |
| `xiaomi-fixed/verification.json` and accompanying captures | Corrected `4060284` build, as identified by the operator record; selected controls tested at font scale 1.45. |
| `pixel-fixed/verification.json` and accompanying captures | Corrected `43537a5` build; selected controls tested at font scale 1.3, including dialog focus/Back, sheet states/bounds, exact text retention and a one-step cursor edit. |
| `xiaomi-install.json` | Preceding `43537a5` build installed successfully, with both legacy files unchanged before launch and no v2 files present at that checkpoint. |
| `pixel-final-install.json`, `xiaomi-final-install.json` | Current `2a1a736` installed on both phones; all four existing legacy/v2 configuration and state files have identical pre/post-install hashes before launch. |
| `v2-preflight.json`, `xiaomi-v2/ready.xml` | Entry/setup observations only. They are not mutual-pairing, account-genesis or membership-commit receipts. |

The current built APK SHA-256 is
`2a1a736512343cdf617bed94af2711d83f54f3035f5bcff3ce6559524a514667`
(339,809,795 bytes). It is installed on both phones; hardware pairing and joint
genesis and independent sign-in passed against the isolated Vapor authority.
The preceding `43537a5` was installed on both phones. Current Swift fixes keep
active ceremonies polling, advance an unjoined inspection to expiry locally, and
serialize one explicit action or QR request after a quiet read without changing
its binding. Quiet reads no longer toggle the visible busy layout. QR display
also rechecks observer/foreground and native context. Kotlin is unchanged, and
the Application suite passes 43 tests. Actual pairing results are maintained
separately from this UI evidence.

Both phones reviewed the same `Pixel-Xiaomi` genesis proposal. The first approval
left zero accounts, owners and credentials; the second committed one account with
two owners and zero credentials. Public checkpoints verify the ledger. This
establishes the isolated pairing/genesis flow through native Copy link and manual
import. Both phones then signed in independently, producing two epoch credentials
with verified root/authority signatures and delegation bindings. The authority
ran separately on port 18191; optical camera scanning and v2 workload submission
are not established by these results.

## Final expiry and polling checks

The final `2a1a736` checks are recorded in public, capability-free evidence:

- [Pixel expiry](../../phone-v2-hardware/final-expiry-verification.json): an
  unjoined inspection expires automatically, shows recovery, and requires no
  restart or manual refresh between inspection and expiry.
- [Pixel layout stability](../../phone-v2-hardware/pixel-inspection-stability.json):
  four samples show identical Join button bounds with no busy banner.
- [Xiaomi quiet polling](../../phone-v2-hardware/xiaomi/quiet-poll/verification.json):
  both pre-deadline QR samples have identical bounds, and all five samples omit
  the busy banner. The invitation expired before the third planned sample, so
  this does not establish the intended full 15-second QR geometry check.

The final-install records above verify all four files individually: legacy client
configuration/state and v2 configuration/state. These are per-install comparisons
before launch, not assertions that later protocol actions never update the journal.

## Failures retained as evidence

- `alert-open*.png` shows a visible dialog, but the matching baseline XML contains
  only the background window. The upstream Android popup omitted `focusable=true`.
  The correction matches the desktop implementation and enables modal Back/key
  handling and active-window accessibility.
- `text-appended.xml` and `text-fast-appended.xml` retain the lost/reordered input
  produced when older Swift echoes replaced newer local edits. The renderer now
  retains local text, selection and composition while those echoes arrive.
- `sheet-closed.xml` and `sheet-dismissed-before-fix.xml` report `Hidden` while
  still exposing sheet content below the bounded preview. The screenshots show
  the same overflow. The adapter now clips both sheet/background layers to the
  requested viewport.

These defects are covered by the current 401 desktop tests plus one Android
properties test, including eleven text-entry regressions and a tall-host sheet
pixel/visibility/open/drag/close regression. Host tests alone are not device proof.

## Corrected Xiaomi smoke

[`xiaomi-fixed/verification.json`](xiaomi-fixed/verification.json) records:

- Button callbacks advance the catalog event count.
- `alert-open.xml` contains the dialog title, message and all three actions;
  `alert-window-focus.txt` identifies the focused popup window.
- Cancel and system Back remove the popup and emit their respective callbacks.
- Hidden and closed sheet captures contain no sheet body; open content stays
  within the preview bounds.
- Fast entry retains the exact expected 21-character suffix after callbacks and
  keyboard dismissal.
- Returning to the identity screen and reopening the catalog retains UI state;
  the displayed legacy key matches before and after.

## Corrected Pixel smoke

[`pixel-fixed/verification.json`](pixel-fixed/verification.json) records the
`43537a5` build at font scale 1.3:

- Button callbacks advance the event count; dialog XML contains the active modal
  controls and the window-focus record identifies the popup.
- System Back dismisses the alert and emits `onDismissRequest`.
- The sheet moves Hidden → Expanded → Hidden; hidden/closed trees omit sheet
  children and inspected screenshots show bounded open content.
- All suffix and inserted characters are retained. A separate Move End, one Left,
  then insertion check puts `Z` before the final `0` as expected.
- Back to SwiftKey returns to the legacy identity screen.

The rapid ten-Left batch did not assert its cursor destination; only the separate
one-Left edit establishes the stated cursor check. These corrected-device runs
establish active-window accessibility and selected-control acceptance, not a full
TalkBack traversal, all 127 surfaces, physical haptic verification, or exhaustive
predictive-back animation/cancellation coverage. The earlier Pixel navigation
captures and recording show an actual Back callback to the root page; they retain
their earlier build context.

## State and publication limits

`pixel-install-state-review.json` records a changed protocol-state hash relative
to its session baseline while the configuration hash stayed equal. It does not,
by itself, establish data loss or an identity reset; it also does not support a
claim that all session bytes stayed unchanged. Initial and final per-install
preservation assertions have narrower, explicit boundaries; the final two-phone
records include all four existing legacy/v2 files.

Published files contain screenshots, UI trees, public observations and comparison
hashes. Pairing capabilities, private configuration/journal contents and signing
keys are not evidence artifacts. Account creation and mutual-consent claims are
supported by the separate protocol evidence linked above, not inferred from
catalog screenshots or installation records.
