# Llama Mail — Kirigami Port Plan (KDE Plasma Desktop/Mobile via Flatpak + Ubuntu Touch via Clickable)

Port of Llama Mail to Linux, third sibling after Android (`~/git/llama-mobile`, the
reference for all wire contracts) and SwiftUI macOS/iOS (this repo). One Qt/QML
codebase, two packaging targets:

| Target | Toolkit | Packaging | Qt |
| --- | --- | --- | --- |
| KDE Plasma Desktop + Plasma Mobile | Kirigami (KF6) | Flatpak (`org.kde.Platform`) | Qt 6 |
| Ubuntu Touch (Lomiri) | Kirigami (KF5, bundled in the click) | Clickable | Qt 5.15 |

New sibling repo: `~/git/llama-mail-qt` (this repo is Xcode-centric; don't nest).

## Locked decisions carried over (do not relitigate)

- **Relay-only.** No IMAP/SMTP anywhere. The relay backend (`mail.urlxl.com`,
  Cloudflare) is the sole transport. Search is local-cache-only.
- **Wire contracts come from `llama-mobile`** (`Mobile_Mail_Relay.md`,
  `Mobile_Contact_Sync.md`) — check the Android implementation, never guess.
  Known-verified shapes:
  - `GET /api/inbox?sub&hash&limit&mailbox&since` → `{tabs, byTab, cursor, delta, removed}`
  - `GET /api/inbox/folders?parent=INBOX|Archive` → `{parent, folders:[{path, deletable}]}` (full paths, `/` and `.` both hierarchy delimiters)
  - `POST /api/inbox/actions` `{action, messageIds, mailbox, targetMailbox}` (move implemented; read/archive/spam/delete are open verbs)
  - `POST /api/mail/send` — `to`/`cc`/`bcc` are **comma-joined strings**, plus `subject`, `body`, `mode`
  - `GET /api/contacts/sync?since` (pull) / `POST {baseCursor, changes:[ContactDto]}` (push); ContactDto has `fn`, `emails[]`, `phones[]` as `{label,value}`, plus `rev`; response `{cursor, tooOld, changed, deleted}`; `tooOld` → reset cursor + wipe cache
  - `POST /api/notifications/native/register` requires exactly `subscriberId`, `pairingToken`, `deviceToken` (+ optional `deviceName`); 400s return plain-text listing missing fields. `normalizeNativePlatform` maps any non-ios/android platform to "android".
  - `/api/notifications/desktop/register` does **not** exist server-side; the web
    frontend's "Pair Desktop App" button fires the same `llamalabels://native-pair`
    deep link as the mobile QR. Do not build a desktop-pair path.
- **13 theme palettes are a binding contract** with web `theme.ts` / Android
  `AppTheme.kt` / this repo's `Style/AppTheme.swift` (easiest transcription
  source). Fonts: Space Grotesk + IBM Plex Mono (both OFL — bundle the TTFs,
  which the Mac port still hasn't done).
- **Attachments, drafts-to-server, delta/cursor mail sync, server search: v2.**
  Every refresh is a full folder snapshot (`since=0`), same as Mac v1.
- **StandardFolder wire names**: `INBOX`, `Drafts`, `Junk`, `Sent`, `Trash`,
  `Archive`; display name splits on both `/` and `.`.
- 90-second foreground refresh cadence (user preference from the Android AGENTS.md).
- License GPL-2.0 (fine with Qt LGPL / KDE).

## Stack decisions (new for this port)

- **Language split**: C++20 core library (`libllamacore`) using only
  QtCore/QtNetwork/QtSql — this subset compiles identically under Qt 5.15 and
  Qt 6, so the dual-Qt problem is confined to QML and glue. UI is one shared
  Kirigami QML tree.
- **QML dual-version strategy**: Qt 5.15 already supports unversioned imports,
  so `import org.kde.kirigami as Kirigami` parses on both. Rules: no KF6-only
  types (no `Kirigami.Delegates`), no removed KF5 types (`BasicListItem`) —
  the style guide forces custom row delegates anyway (see EmailListRow). One
  small `Compat` QML singleton for anything that genuinely diverges. Type
  registration via classic `qmlRegisterType` calls (works on both; skip
  `QML_ELEMENT` codegen).
- **Persistence**: SQLite via `QSqlDatabase` (replaces SwiftData). Plain
  hand-written DAOs mirroring EmailDAO/ContactDAO/PushNotificationDAO — no ORM
  dependency.
- **Secrets** (sub/hash pairing credentials, replaces Keychain):
  - Flatpak: QtKeychain → Secret Service portal.
  - Ubuntu Touch: no Secret Service; store in the AppArmor-confined app data dir
    with 0600 perms behind the same `SecureStore` interface. `ponytail:` upgrade
    path = UT online-accounts/keyring if one materializes.
- **HTML email rendering**: `WebEngineView` on both (KDE runtime ships
  QtWebEngine; UT ships QtWebEngine 5.15 — it powers Morph). Reuse the themed
  CSS scaffold from `EmailDetailView.swift` / Android `EmailDetailActivity`,
  colors injected as hex from the active palette. Intercept navigation →
  `Qt.openUrlExternally`. Plain-text bodies render as mono `Text`.
- **Push notifications**: there is no APNs/FCM equivalent the backend supports
  on Linux. **v1 is pull-polling only** (90 s foreground timer; UT gives apps
  no background execution, and Flatpak has no push service). The whole
  PushRepository/cursor/dedupe machinery still ports — it drives the polling
  path today. MFA approval works whenever the app is foregrounded or polled.
  v2 options, both requiring backend work in `llama-labels/server.go`:
  UBports push (`push.ubports.com`) and/or UnifiedPush as new provider types
  in `/api/notifications/native/register`.
- **Deep links** (`llamalabels://native-pair?...`):
  - Flatpak: `.desktop` with `MimeType=x-scheme-handler/llamalabels;`,
    `KDBusService(Unique)` + `%u` Exec arg routes the URL into the running instance.
  - Ubuntu Touch: `urls` hook in the click manifest (url-dispatcher).
  - Paste-link pairing stays as the universal fallback (parity with macOS);
    camera QR scan is v2 (UT camera APIs differ; not worth v1 scope).
- **Desktop notifications** (for mail found by polling): KNotifications on
  Plasma; Lomiri push/notification API is push-server-bound, so UT v1 relies on
  in-app badge + list refresh only.
- **Adaptive UI instead of two roots**: where SwiftUI needed `MainTabView` +
  `MacRootView`, Kirigami's whole point is one responsive tree —
  `Kirigami.ApplicationWindow` + `GlobalDrawer` (folders + keyword filters, the
  macOS sidebar equivalent) + `Kirigami.PageRow` (list/detail columns on wide
  screens, stacked pages on phones). Skip pop-out windows and drag-to-folder in
  v1 (context-menu "Move to…" covers it); both are desktop-polish v2.

## Repo layout

```
llama-mail-qt/
  CMakeLists.txt              # ECM + Qt5/Qt6 dual (QT_MAJOR_VERSION switch)
  core/                       # libllamacore — QtCore/Network/Sql only
    models/                   # Email, Contact, KeywordSettings, MfaChallenge, PushNotification, StandardFolder
    net/                      # HttpClient (QNAM wrapper, stub-injectable), RelayMailSource,
                              # ContactSyncClient, NativeRegistrationClient, MfaResponseClient, PushNotificationClient
    db/                       # Database bootstrap + EmailDao, ContactDao, PushDao (SQLite)
    stores/                   # SecureStore (per-platform), settings stores (QSettings), cursor stores
    domain/                   # MailRepository, KeywordRepository, ContactSyncRepository+Reconciliation,
                              # PushRepository, SendEmail/ApproveMfa use cases, DeviceRegistrationService, PollingScheduler
    theme/                    # 13 palettes + ThemeManager (QObject exposing colors/fonts to QML)
  app/
    main.cpp                  # DI graph (SingletonGraph equivalent), qmlRegisterType, deep-link routing
    qml/
      Main.qml                # ApplicationWindow + GlobalDrawer + PageRow
      pages/                  # InboxPage, EmailDetailPage, ComposePage, ContactsPage, ContactDetailPage,
                              # SettingsPage, ThemesPage, KeywordSettingsPage, PairingPage, MfaApprovalPage
      components/             # EmailListRow, KeywordTabBar, Avatar, EmptyState, StatusBadge, ThemedButton
  tests/                      # QtTest, stubbed HttpClient — port the Mac suite's coverage
  packaging/
    flatpak/com.urlxl.llamamail.json
    click/ (clickable.yaml, manifest.json, llamamail.apparmor, .desktop, urls hook)
  po/                         # gettext catalogs seeded from Localizable.xcstrings keys
```

## Phases

**Phase 1 — Skeleton that ships (de-risk packaging first).**
CMake workspace building `libllamacore` + a hello Kirigami window under BOTH
Qt 6 (Flatpak, `org.kde.Platform` latest) and Qt 5.15 (Clickable,
`ubuntu-sdk-20.04`, Kirigami/ECM built via `clickable.yaml` `libraries:`).
Deep-link plumbing proven on both (`.desktop` scheme handler; UT `urls` hook).
This phase intentionally front-loads the two biggest unknowns: Kirigami-in-click
build cost and the KF5/KF6 QML compat rules. Exit: both packages install and
open a window on real targets (Plasma desktop + a UT device/emulator).

**Phase 2 — Core data.** Models, SQLite schema + DAOs, QSettings-backed
settings stores (keyword visibility, contacts settings, theme choice), cursor
stores, `SecureStore` with the two backends. Tests for DAO round-trips.

**Phase 3 — Relay networking.** `HttpClient` wrapper (async, stub-injectable),
then port each client against the verified contracts above, translating from
this repo's `Data/Networking/*` (they're already relay-only and correct).
Lock the `/register` body shape and send comma-joining with tests exactly like
the Mac suite does — those tests exist because guessed shapes caused live 400s.

**Phase 4 — Domain.** MailRepository (DAO-cached snapshots), KeywordRepository
tab computation, ContactSyncRepository + reconciliation (push/pull split,
`tooOld` reset+wipe), PushRepository (seq dedupe, cursor), use cases,
DeviceRegistrationService, PollingScheduler (90 s QTimer, pause on suspend via
`Qt.application.state`). Port ContactSyncTests/PushTests/MailTests coverage.

**Phase 5 — Theme system + components.** Transcribe the 13 palettes from
`Style/AppTheme.swift` (values are the binding contract — copy, don't
approximate). ThemeManager as a QML-exposed singleton; components drawn to
STYLE_GUIDE.md (custom delegates, not Kirigami defaults, so the KF5/KF6
delegate divergence never matters). Bundle the two font families via
QFontDatabase.

**Phase 6 — Screens.** All pages in one adaptive tree. Inbox: keyword tab bar +
folder tree in the GlobalDrawer (Inbox → subfolders → keywords → Drafts/Junk/
Sent/Trash → Archive → subfolders, per the macOS sidebar order; subfolders from
`/api/inbox/folders`, loaded once). EmailDetail: HTML-sniff → WebEngineView with
themed scaffold, else mono text; "Move to…" action. Compose. Contacts
list/detail (read-only header-card → edit flow, as redesigned on macOS).
Settings (Kirigami FormLayout pages: Connection/Appearance/Keywords/
Notifications — same panes as MacPreferencesView). Pairing page (paste link +
deep link → register → auto-enable relay). MFA approval page.

**Phase 7 — Platform integration.** KDBusService single-instance + deep-link
routing into a running app; KNotifications for polled new-mail/MFA on Plasma
(with tap-through navigation, mirroring PushNotificationDispatcher's
onNavigate); UT lifecycle handling (aggressive app suspension — refresh on
resume); Plasma Mobile ergonomics pass (drawer reachability, touch targets).

**Phase 8 — Packaging & polish.** App icon (reuse the Dark Matter envelope;
regeneration script exists at `/tmp/make_llama_icon.swift` — re-render to
hicolor sizes), AppStream metainfo, gettext extraction seeded from
`Localizable.xcstrings` keys, Flathub-ready manifest, OpenStore-ready click,
TESTING.md checklist (mirror the Mac one: live pairing against
`mail.urlxl.com`, folder fetch, send, contact sync, MFA via polling), CI
(GitHub Actions: flatpak-builder + `clickable build` in Docker).

## Risks / verify-early list

1. **UT framework reality check** (Phase 1): confirm current stable framework is
   still Qt 5.15/`ubuntu-sdk-20.04` and that Kirigami KF5 + ECM build cleanly as
   Clickable libraries. If UT's Qt6 framework has landed by build time, the
   dual-Qt burden mostly evaporates — check first.
2. **QtWebEngine availability**: confirm it's in the chosen `org.kde.Platform`
   runtime (else add the module to the manifest) and linkable from a click.
   Fallback: `Text.RichText` renders degraded HTML — acceptable emergency
   fallback, not the plan.
3. **KF5/KF6 QML drift**: budget for the Compat singleton; test both targets
   every phase, not at the end.
4. **No push on Linux** is a product regression vs iOS/Android — make the v1
   polling-only story explicit in the README so it's not mistaken for a bug;
   MFA approvals only arrive while the app runs.
5. **Cloudflare + QNAM**: mail.urlxl.com sits behind Cloudflare; bare
   urlxl.com returns 530. Set a real User-Agent early in case CF challenges
   default Qt UA strings.
