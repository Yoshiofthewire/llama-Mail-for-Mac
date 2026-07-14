# Llama Mail — KDE Client Plan (Flatpak for Plasma Desktop + Plasma Mobile)

Fourth sibling after Android (`~/git/llama-mobile`), SwiftUI macOS/iOS (this repo),
and the drafted-but-unstarted dual-target Qt plan (`Kirigami_llama_mail.md`).
**This plan supersedes the KDE half of `Kirigami_llama_mail.md`.** Ubuntu Touch is
out of scope here; the shared-core rules below deliberately keep that door open.

One codebase, one package:

| Target | Toolkit | Packaging | Qt |
| --- | --- | --- | --- |
| KDE Plasma Desktop + Plasma Mobile | Kirigami (KF6) | Flatpak (`org.kde.Platform` 6.x) | Qt 6 only |

New sibling repo: `~/git/llama-mail-qt` (this repo is Xcode-centric; don't nest).
Suggested app ID: `com.urlxl.LlamaMail` (Flathub wants a domain you control).

## What changed since the last Qt plan (2026-07-11 → now)

These are the lessons learned that reshape the plan:

1. **UnifiedPush landed** (backend commits `cb96ae0`, `510eba6`, `21a20b8` in
   `~/git/llama-labels`; Android commits `4782ce7`, `8ef0398` in `~/git/llama-mobile`;
   architecture doc `llama-labels/UNIFIEDPUSH_IMPLEMENTATION.md`). The old plan's
   biggest product regression — "polling-only v1, no push on Linux" — is gone.
   v1 gets real push via **KUnifiedPush** (KDE's UnifiedPush connector library +
   distributor daemon, ntfy-backed). Backend explicitly anticipated this client:
   *"KDE Mobile / Ubuntu Touch clients call the same
   `/api/notifications/native/register` endpoint with `transport=unifiedpush`."*
2. **Qt 5 compatibility is no longer a v1 constraint.** Dropping the dual-Qt
   requirement from the deliverable kills the riskiest phase of the old plan
   (Kirigami-in-click, KF5/KF6 QML compat rules, Compat singleton). We still keep
   `libllamacore` to QtCore/QtNetwork/QtSql only — that costs nothing and preserves
   the Ubuntu Touch option — but QML is written for KF6 without compat gymnastics.
3. **The backend grew features since the old plan was written** (all shipped for
   the Mac client, most uncommitted-then, now in `llama-labels` history):
   - All `/api/inbox/actions` verbs are real: `move`, `read`, `archive`, `spam`,
     `delete` (delete moves to Trash; expunges when the mailbox IS Trash).
   - Attachments: `GET /api/mail/attachments`, `GET /api/mail/attachment`
     (messageId = IMAP UID), and `attachments:[{name,mimeType,dataBase64}]` on
     send (25 MB decoded cap, 40 MB body limit). Contract in
     `llama-mobile/Mobile_Mail_Relay.md`.
   - Send supports `mode: "plain" | "html" | "markup"`.
   - Registration dedupe: server upserts by pushToken+platform; clients send
     their stored `deviceId` on re-registration (otherwise every register call
     used to append a duplicate device row).
4. **Known live-system gotchas to inherit, not rediscover:**
   - Re-registration silently 401s once the short-lived `pairingToken` expires —
     token rotation after pairing never reaches the server (latent, unfixed).
     Don't design the KDE client to re-register on every launch and assume it works.
   - `mail.urlxl.com` sits behind Cloudflare (bare `urlxl.com` → 530). Set a real
     User-Agent on QNAM from day one.
   - Deployment lag: backend deploys via the user's Docker pipeline on a remote
     host. **Verify the UnifiedPush commits are actually deployed to
     `mail.urlxl.com` before any live E2E** — the attachments endpoints had the
     same "committed but 404s live" window.

## Locked decisions carried over (do not relitigate)

- **Relay-only.** No IMAP/SMTP anywhere. `mail.urlxl.com` is the sole transport.
  Search is local-cache-only.
- **Wire contracts come from `llama-mobile`** (`Mobile_Mail_Relay.md`,
  `Mobile_Contact_Sync.md`) and, for post-July-2026 features, this repo's
  `Data/Networking/*` Swift clients (they are relay-only, live-verified, and
  test-locked). Never guess shapes — guessed shapes caused live 400s twice.
  Verified inventory:
  - `GET /api/inbox?sub&hash&limit&mailbox&since` → `{tabs, byTab, cursor, delta, removed}`
  - `GET /api/inbox/folders?parent=INBOX|Archive` → `{parent, folders:[{path, deletable}]}`
    (full paths; `/` and `.` are both hierarchy delimiters)
  - `POST /api/inbox/actions` `{action: move|read|archive|spam|delete, messageIds, mailbox, targetMailbox}`
  - `POST /api/mail/send` — `to`/`cc`/`bcc` are **comma-joined strings**, plus
    `subject`, `body`, `mode`, optional `attachments[]`
  - `GET /api/contacts/sync?since` (pull) / `POST {baseCursor, changes:[ContactDto]}`
    (push); ContactDto: `fn`, `emails[]`/`phones[]` as `{label,value}`, `rev`;
    response `{cursor, tooOld, changed, deleted}`; `tooOld` → reset cursor + wipe cache
  - `POST /api/mfa/push/respond` — auth in the JSON **body**
    (`subscriberId`, `subscriberHash`, `deviceId`, `approve`), not query params
- **13 theme palettes are a binding contract** with web `theme.ts` / Android
  `AppTheme.kt` / this repo's `Style/AppTheme.swift` (easiest transcription
  source — copy values, don't approximate). Fonts: Space Grotesk + IBM Plex Mono
  (OFL; bundle the TTFs).
- **StandardFolder wire names**: `INBOX`, `Drafts`, `Junk`, `Sent`, `Trash`,
  `Archive`; display name splits on both `/` and `.`.
- 90-second foreground refresh cadence. Full-snapshot refresh (`since=0`);
  delta/cursor mail sync stays v2.
- Every mail-cache/persistence/reconciliation behavior should port from the Mac
  suite's test coverage (159 tests) — that suite encodes every contract fix.
- License GPL-2.0.

## Push: the UnifiedPush contract (new, the heart of this plan)

### Registration

`POST /api/notifications/native/register` with:

```json
{
  "subscriberId": "...",
  "subscriberHash": "...",
  "pairingToken": "...",
  "deviceToken": "https://ntfy.sh/<topic-from-distributor>",
  "deviceId": "<stored id, on re-registration>",
  "platform": "linux",
  "transport": "unifiedpush",
  "deviceName": "<hostname>"
}
```

- `deviceToken` **is the UnifiedPush endpoint URL** handed to us by the
  distributor — not an opaque token.
- `transport: "unifiedpush"` is mandatory for us: `normalizeNativeTransport`
  falls back to platform-derived routing when transport is empty, and
  `normalizeNativePlatform` maps any non-ios/android platform (including
  "linux") to **"android" → FCM**, which would send our pushes into the FCM
  relay and fail. An unknown transport string also silently becomes "fcm" —
  spell it exactly.
- The server validates the endpoint against SSRF
  (`ValidateUnifiedPushEndpointURL`): **https only, no private/loopback/
  link-local hosts, re-checked at dial time, redirects disabled.** Consequence
  for development: a self-hosted ntfy on localhost/LAN will be **rejected at
  registration**. Live tests must use a public endpoint (hosted ntfy.sh works
  without an account).
- The register response echoes the stored `transport` (Android round-trips it
  into its UI); persist what the server says, not what we sent.

### Delivery

The backend POSTs the payload **directly** to the endpoint (no Cloudflare relay
in the path). The distributor hands the app the raw bytes:

```json
{
  "title": "<sender>",
  "body": "<subject>",
  "data": {
    "messageId": "...", "sender": "...", "subject": "...",
    "senderName": "...", "emailSubject": "...",
    "Keywords": "comma,separated", "title": "...", "body": "...",
    "url": "/read"
  }
}
```

(Envelope from `UnifiedPushSender.Send` in
`backend/internal/processor/native_sender.go`; `data` keys from
`buildNativePushData` in `poller.go`. Note the capital-K `Keywords`.)

Parse the **envelope** and feed `data` into the ported PushPayloadParser
(`messageId` required; `senderName`/`emailSubject`/`Keywords` drive the
notification and dedupe).

> ⚠️ **Android reference bug — do not copy it:** `LlamaUnifiedPushService.onMessage`
> decodes the message as a flat `Map<String,String>`, but the backend sends the
> nested envelope above. The nested `data` object makes that decode throw →
> `getOrNull()` → **every UnifiedPush mail notification is silently dropped** on
> Android as committed. The KDE client must parse `{title, body, data}`; the
> Android fix is a separate task (noted below).

- 404/410 from the endpoint ⇒ backend marks the device **stale and deletes the
  registration** (same behavior that bit us with APNs BadDeviceToken). If the
  user switches distributors, re-register promptly or pushes stop and the
  device row vanishes → full re-pair required.
- **MFA challenges are NOT sent over UnifiedPush** (endpoints are public URLs;
  payloads unencrypted — `dispatchPushChallenge` filters
  `transport == "unifiedpush"` devices). MFA approval therefore works only via
  the polling path while the app runs, exactly like the old plan. Lifting this
  needs RFC 8291 encryption on the backend; KUnifiedPush already supports
  RFC 8291/8292 client-side, so the client should surface its Web Push crypto
  keys behind a `ponytail:` when the backend catches up.

### Client integration: KUnifiedPush

- Link **`KUnifiedPush::Connector`** (repo: [KDE/kunifiedpush](https://github.com/KDE/kunifiedpush)) —
  create a Connector instance, receive the endpoint URL, register it with our
  backend, connect `messageReceived`. It speaks the UnifiedPush D-Bus spec to
  whatever distributor is present (kunifiedpush-distributor with Gotify/
  Autopush/NextPush/Ntfy providers, or any spec-compliant distributor).
- **Bundle the connector library in the Flatpak** (it's a small KDE lib, not in
  the runtime). The **distributor daemon runs on the host** — it is not
  flatpak'd (per the [F-Droid 5-years retrospective](https://f-droid.org/2026/01/08/unifiedpush-5-years.html),
  Flatpak publication of the distributor is still an open goal). Plasma
  distros/Plasma Mobile can ship it; other desktops need the distro package.
- **Graceful degradation is a hard requirement:** no distributor on the host ⇒
  the app falls back to the 90 s polling scheduler automatically and says so in
  Settings ("Push: unavailable — install a UnifiedPush distributor; using
  polling"). Mirror the Android fallback semantics: registration failed /
  unregistered ⇒ drop back (Android falls back to FCM; we fall back to polling)
  and surface the reason through the same syncError channel the pairing UI shows.
- **Background delivery:** the distributor D-Bus-activates the app when a push
  arrives — this is how mail notifications work with the app closed. The app
  must be D-Bus activatable (`DBusActivatable=true`, exported `.service` file —
  Flatpak exports these automatically) and, when activated for a push, show a
  KNotification without raising a window. Verify activation actually works
  from inside the sandbox in Phase 1 (this is the single biggest v1 unknown).
- Even with push, keep the whole PushRepository seq-dedupe/cursor machinery from
  the Mac port — pushes and polls race, and dedupe-by-seq is what makes that safe.

## Stack decisions

- **Language split**: C++20 core library (`libllamacore`, QtCore/QtNetwork/QtSql
  only — keeps the UT door open) + KF6 Kirigami QML app layer. QtDBus/KUnifiedPush/
  KNotifications glue lives in the app layer, never in core.
- **QML**: Qt 6 idioms allowed now (`QML_ELEMENT`, versionless imports). Custom
  row delegates per STYLE_GUIDE.md rather than Kirigami defaults (styling
  requirement, and it keeps core visuals identical to the other clients).
- **Persistence**: SQLite via `QSqlDatabase`, hand-written DAOs mirroring
  EmailDAO/ContactDAO/PushNotificationDAO. No ORM.
- **Secrets** (sub/hash/deviceId/pairing credentials): QtKeychain → Secret
  Service portal (bundle QtKeychain in the manifest).
- **HTML mail rendering**: QtWebEngine `WebEngineView`. In the Qt 6 Flatpak
  world QtWebEngine is **not** in `org.kde.Platform` — use the
  `io.qt.qtwebengine.BaseApp` baseapp (verify current name/branch on Flathub in
  Phase 1). Reuse the themed CSS scaffold from `EmailDetailView.swift` /
  Android `EmailDetailActivity`, palette colors injected as hex; intercept
  navigation → `Qt.openUrlExternally`; plain-text bodies render as mono `Text`.
- **Deep links** (`llamalabels://native-pair?...`): `.desktop` entry with
  `MimeType=x-scheme-handler/llamalabels;`, `KDBusService(Unique)` routes URLs
  into the running instance. Paste-link pairing is the universal fallback;
  camera QR scan is v2 (Plasma Mobile camera stack not worth v1 scope).
- **Notifications**: KNotifications (works via the portal in Flatpak), with
  tap-through navigation mirroring PushNotificationDispatcher's `onNavigate`
  (mail → open message, MFA → approval page).
- **Adaptive UI, one tree**: `Kirigami.ApplicationWindow` + `GlobalDrawer`
  (folder tree + keyword filters — the macOS sidebar equivalent) +
  `Kirigami.PageRow` (list/detail columns on desktop, stacked pages on mobile).
  No pop-out windows, no drag-to-folder in v1 (context-menu "Move to…" covers it).

## v1 scope (relative to the current Mac client)

In: pairing (paste-link + deep-link), inbox with keyword tabs + folder tree +
subfolders, full mail actions (read/archive/junk/delete/move), HTML mail
viewing, plain-text compose (reply/reply-all/forward), **attachment viewing +
download** (endpoints exist; save via the file chooser portal), contacts
list/detail with sync + reconciliation, settings (Connection/Appearance/
Keywords/Notifications), 13 themes, MFA approval (polling-driven),
**UnifiedPush notifications** with polling fallback.

Out (v2): compose attachments, rich-text/HTML compose, server drafts, camera QR
pairing, delta/cursor mail sync, encrypted push (backend-gated) and therefore
MFA-over-push, drag-and-drop, multi-select.

## Repo layout

```
llama-mail-qt/
  CMakeLists.txt              # ECM, Qt6/KF6
  core/                       # libllamacore — QtCore/Network/Sql only
    models/                   # Email, Contact, KeywordSettings, MfaChallenge, PushNotification, StandardFolder
    net/                      # HttpClient (QNAM wrapper, stub-injectable, real UA), RelayMailSource,
                              # ContactSyncClient, NativeRegistrationClient (transport-aware), MfaResponseClient
    db/                       # Database bootstrap + EmailDao, ContactDao, PushDao
    stores/                   # SecureStore (QtKeychain-backed), settings stores (QSettings), cursor stores
    domain/                   # MailRepository, KeywordRepository, ContactSyncRepository+Reconciliation,
                              # PushRepository (seq dedupe/cursor), SendEmail/ApproveMfa use cases,
                              # DeviceRegistrationService, PollingScheduler
    theme/                    # 13 palettes + ThemeManager (QObject → QML)
  app/
    main.cpp                  # DI graph, KDBusService, deep-link routing, push-activation entry
    push/                     # KUnifiedPush Connector glue, payload envelope parser, KNotifications dispatcher,
                              # transport state machine (unifiedpush ⇄ polling fallback)
    qml/
      Main.qml                # ApplicationWindow + GlobalDrawer + PageRow
      pages/                  # InboxPage, EmailDetailPage, ComposePage, ContactsPage, ContactDetailPage,
                              # SettingsPage, ThemesPage, KeywordSettingsPage, PairingPage, MfaApprovalPage
      components/             # EmailListRow, KeywordTabBar, Avatar, EmptyState, StatusBadge, ThemedButton
  tests/                      # QtTest, stubbed HttpClient — port the Mac suite's coverage
  packaging/flatpak/com.urlxl.LlamaMail.json (+ metainfo, .desktop, icons)
  po/                         # gettext catalogs seeded from Localizable.xcstrings keys
```

## Phases

**Phase 1 — Skeleton that pushes (de-risk push + packaging together).**
CMake workspace, hello-Kirigami window, Flatpak manifest building against
`org.kde.Platform` 6.x with the QtWebEngine baseapp and bundled
KUnifiedPush/QtKeychain modules. Prove, on a real Plasma desktop with
kunifiedpush-distributor installed: (a) Connector gets an ntfy.sh endpoint from
inside the sandbox, (b) a manual `curl -d '{"title":"t","body":"b"}' <endpoint>`
reaches the app, (c) **D-Bus activation delivers a push with the app closed**,
(d) `llamalabels://` deep link opens/focuses the app. Exit: all four proven, or
fallbacks chosen deliberately. Also confirm in this phase whether the live
`mail.urlxl.com` has the UnifiedPush commits deployed.

**Phase 2 — Core data.** Models, SQLite schema + DAOs, settings/cursor stores,
SecureStore. DAO round-trip tests.

**Phase 3 — Relay networking.** HttpClient wrapper, then each client against
the verified contracts, translated from this repo's `Data/Networking/*`.
Test-lock the register body (with `transport`/`deviceId`), send comma-joining,
action verbs, and the attachments endpoints — exactly the shapes the Mac tests
lock, because every one of those tests exists due to a live failure.

**Phase 4 — Domain + push plumbing.** MailRepository (DAO-cached snapshots),
KeywordRepository tab computation, ContactSyncRepository + reconciliation
(`tooOld` reset+wipe), PushRepository (seq dedupe, cursor; synthesized ms-epoch
seqs for push-mode arrivals, as on Mac), DeviceRegistrationService (registers
the UnifiedPush endpoint; re-registers on endpoint change; **does not**
re-register blindly on launch given the expired-pairingToken 401), the
transport state machine (distributor present ⇒ push + polling paused to a slow
cadence; absent/failed ⇒ 90 s polling), envelope parser (with a test pinning
the exact backend JSON, including nested `data` and capital-K `Keywords`).
Port MailTests/PushTests/ContactSyncTests/NetworkingTests coverage.

**Phase 5 — Theme system + components.** Transcribe the 13 palettes from
`Style/AppTheme.swift`. ThemeManager as QML singleton; STYLE_GUIDE.md
components; bundle the two font families via QFontDatabase.

**Phase 6 — Screens.** All pages in the one adaptive tree. Inbox: keyword tab
bar + GlobalDrawer folder tree (Inbox → subfolders → keywords → Drafts/Junk/
Sent/Trash → Archive → subfolders, macOS sidebar order; subfolders loaded once
from `/api/inbox/folders`). Mail actions via swipe (mobile: left=Archive,
right=Delete, Android gesture parity) and context menu (Archive/Move to…/Junk/
Delete). EmailDetail: HTML-sniff → WebEngineView, six-action row, attachment
chips → portal save. Compose (plain text, reply/reply-all/forward). Contacts
(read-only header card → edit flow). Settings (Kirigami FormLayout:
Connection/Appearance/Keywords/Notifications; Notifications pane shows the
active transport — push vs polling — mirroring the web frontend's new
transport badge). Pairing page. MFA approval page.

**Phase 7 — Platform integration.** KNotifications with tap-through
navigation; push-activation cold-start path (parse payload → notify → exit or
stay resident per config); polling pause/resume on `Qt.application.state`;
Plasma Mobile ergonomics pass (drawer reachability, touch targets, on-screen
keyboard vs compose). Live E2E against `mail.urlxl.com`: pair, register with a
real ntfy.sh endpoint, receive a real mail push, verify MFA still arrives via
polling only, verify a deleted ntfy topic gets the device row cleaned up
server-side (stale handling) and that the app detects and re-pairs.

**Phase 8 — Packaging & polish.** App icon (reuse the Dark Matter envelope;
regenerate to hicolor sizes), AppStream metainfo, gettext catalogs seeded from
`Localizable.xcstrings` keys, Flathub-ready manifest + finish-args audit
(wayland/fallback-x11, `--share=network`, D-Bus names for the UnifiedPush
distributor, notification + secret + filechooser portals), TESTING.md checklist
mirroring the Mac one, CI (GitHub Actions flatpak-builder).

## Risks / verify-early list

1. **Distributor availability** is the whole push story: kunifiedpush-distributor
   is a host-side daemon, not flatpak-able today. Confirm it's present/available
   on target systems (Plasma Mobile image? distro packages for desktop?) and
   make the polling fallback + Settings messaging first-class, not an
   afterthought. README must state that push requires a UnifiedPush distributor.
2. **D-Bus activation from the sandbox** (Phase 1 item c). If a spec/sandbox gap
   blocks it, v1 degrades to "push while running, polling badge otherwise" —
   decide explicitly, don't discover it in Phase 7.
3. **Payload envelope mismatch**: the backend UnifiedPush envelope is nested;
   the committed Android receiver parses it as flat and drops everything.
   Someone must fix Android (separate task in `llama-mobile`); until a client
   has received a live UnifiedPush mail notification end-to-end, treat the
   envelope shape as unverified-live and pin it with tests against the backend
   source, not the Android client.
4. **SSRF validation vs local testing**: private/loopback ntfy endpoints are
   rejected at registration. Plan all push testing around public ntfy.sh topics.
5. **Stale-endpoint deletion**: 404/410 ⇒ server deletes the device (same trap
   as APNs BadDeviceToken). Handle distributor switches by immediate
   re-registration, and make re-pair recovery a tested path.
6. **QtWebEngine baseapp**: confirm `io.qt.qtwebengine.BaseApp` branch matches
   the chosen `org.kde.Platform` version; fallback `Text.RichText` is an
   emergency option only.
7. **Cloudflare + QNAM**: set a real User-Agent before the first live request.
8. **MFA-over-push is backend-gated** (needs RFC 8291 encryption server-side;
   KUnifiedPush client support already exists). Keep the client's MFA path
   polling-driven and don't promise push-MFA in UI copy.
9. **Deployment lag**: no live E2E until the UnifiedPush backend commits are
   deployed on the user's Docker host.
