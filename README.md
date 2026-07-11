# llama Mail for Mac

A native SwiftUI mail client for macOS and iOS that connects to a llama-labels mail relay. It is a port of the Android reference app (`llama-mobile`), sharing the same wire contracts, theme palettes, and pairing flows.

The app talks only to the relay backend — there is no direct IMAP/SMTP. You pair a device once (QR code or deep link) and the relay handles mail access, server-side keyword tabs, push notifications, and contact sync.

## Features

- **Inbox with keyword tabs** — the relay categorizes mail into tabs/labels; tab visibility is configurable in settings.
- **Server folders** — Inbox (plus its subfolders), Drafts, Junk, Sent, Trash, and Archive with subfolders. On macOS these live in the sidebar; on iOS they're in the folder menu on the Inbox screen.
- **HTML email rendering** — themed WebKit reader on both platforms; links open in the default browser. Plain-text messages render natively.
- **macOS niceties** — three-pane split view, pop-out email windows (double-click or right-click a message), a toggleable preview pane, drag-and-drop of emails onto sidebar folders to move them, menu-bar commands (⌘N compose, ⌘R refresh, ⌘⇧S contact sync), and a native Preferences window (⌘,).
- **Compose & send** through the relay.
- **Push notifications** (APNs) for new mail and MFA challenges, with a pull-polling fallback (90 s foreground, background refresh on iOS).
- **MFA approval** — approve login challenges from a notification tap.
- **Contact sync** — two-way sync with the relay, with local-first edits and conflict-safe reconciliation.
- **13 themes** — palettes shared verbatim with the web and Android apps.

## Requirements

- Xcode 26 (deployment target macOS/iOS 26.5)
- A running llama-labels backend (the live deployment is behind Cloudflare at `mail.urlxl.com`)
- For push: an APNs key configured on the backend

No external Swift package dependencies — persistence is SwiftData, networking is URLSession, rendering is WebKit.

## Getting started

1. Open `llama Mail for Mac.xcodeproj` in Xcode.
2. Select the *llama Mail for Mac* scheme and your destination (My Mac or an iOS device/simulator).
3. Build and run.
4. Pair the device: in the web frontend, open **Notifications → Pair Desktop App** (or scan the mobile pairing QR on iOS). The `llamalabels://native-pair?...` deep link registers the device and stores credentials in the Keychain.

Until a device is paired, the inbox shows a prompt directing you to Settings → Connection.

## Architecture

The target builds for both platforms from one codebase, laid out in `llama Mail for Mac/`:

| Layer | Contents |
| --- | --- |
| `App/` | Entry point, scenes, app delegate, DI graph (`SingletonGraph`), polling scheduler, notification dispatcher |
| `Data/` | Relay clients (`RelayMailSource`, sync/push/registration clients), SwiftData DAOs and entities, Keychain and settings stores |
| `Domain/` | Models, repositories (mail, keywords, contacts, push), use cases (send, pairing, MFA) |
| `Presentation/` | Shared SwiftUI screens and view models, macOS-specific root/preferences views, style-guide components |
| `Style/` | Theme palettes and manager (binding contract with web `theme.ts` / Android `AppTheme.kt`) |

Platform split: iOS uses a tab layout (`MainTabView`); macOS uses `NavigationSplitView` (`MacRootView`) plus a per-email `WindowGroup` for pop-out readers.

### Wire contracts

The relay endpoints and payload shapes are defined by the Android reference repo (`llama-mobile`), primarily `Mobile_Mail_Relay.md` and `Mobile_Contact_Sync.md`:

- `GET /api/inbox` — emails grouped by tab (`{tabs, byTab, cursor, delta, removed}`)
- `GET /api/inbox/folders?parent=` — folder listing (full paths, e.g. `INBOX/Receipts`)
- `POST /api/inbox/actions` — bulk read/archive/spam/delete/move
- `POST /api/mail/send` — comma-joined recipient strings
- `GET/POST /api/contacts/sync` — cursor-based contact sync
- `POST /api/notifications/native/register` — APNs device registration

When touching any of these, check the Android implementation first rather than guessing.

## Testing

Unit tests use Swift Testing (`@Test`/`#expect`) and live in `llama Mail for MacTests/`; UI test stubs are in `llama Mail for MacUITests/`. Run them in Xcode (⌘U) or:

```sh
xcodebuild test -project "llama Mail for Mac.xcodeproj" -scheme "llama Mail for Mac"
```

Network-facing tests run against a stubbed `HTTPClient` — no backend needed.

## Known gaps (v2 candidates)

- Attachments (compose and viewing)
- Mail cursor/delta sync — every refresh is a full folder snapshot
- Read/archive/delete actions from the reader (move-via-drag exists on macOS)
- Drafts saved to the server
- Server-side search (search runs against the local cache)
- QR scanning via camera on macOS (paste-link and deep-link pairing work)

## License

GPL-2.0 — see [LICENSE.txt](LICENSE.txt).
