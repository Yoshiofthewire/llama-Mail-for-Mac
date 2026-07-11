# Llama Mail — Testing & Release Checklist

Status as of 2026-07-10. Automated suite: **110/110 passing** (`⌘U` or
xcode-tools `RunAllTests`). This file tracks the spec §11 manual E2E checklist
and the release steps that need real infrastructure or human judgment.

## Automated coverage (done, runs in CI/locally)

- Deep-link parsing & validation (native-pair + desktop pairing links)
- Pairing/registration endpoint resolution (`reg` override vs derived)
- Payload mappers (APNs → mail/MFA, capital-K `Keywords` contract)
- Relay response mapping, comma-string send body contract
- Keyword → tab computation + visibility filtering
- Contact sync push/pull, reconciliation (content/order UID matching),
  tombstones, `tooOld` cursor reset
- Pull-mode dedupe by `seq`, cursor advance after handoff
- Keychain round-trips (SecurePairingStore, desktop session, IMAP password)
- SwiftData DAO CRUD (emails, contacts, notification history)
- Theme palette contract (13 themes, hex spot-checks vs theme.ts)
- Desktop pairing code validation + registration client (401/409/429)

## Verified live (2026-07-10, macOS, local relay stub)

Stub: `/tmp/llama_relay_stub.py` (127.0.0.1:8787). Evidence: stub request log.

- [x] Deep link `llamalabels://native-pair?...` opens the app and pairs
- [x] Registration POSTs real APNs device token, `platform`, pairing token
- [x] Pairing persists to Keychain; survives relaunch; auto-switches to relay mode
- [x] Re-registration on app foreground
- [x] Pull-mode polling with `sub`/`hash` auth and `after` cursor
- [x] Relay inbox fetch (`GET /api/relay/folder`) populates the inbox

## Manual E2E — needs real backend / devices (spec §11)

- [ ] Pair against the production relay (scan QR from web app on iPhone;
      paste link on Mac)
- [ ] Inbox tab filtering by keyword with real mail
- [ ] Compose & send through the relay; verify delivery
- [ ] Push mode: real email → APNs → system notification appears
      (device only; APNs does not reach the simulator)
- [ ] MFA challenge push → Approve/Deny action buttons work; in-app
      fallback via notification tap
      - Simulator: `xcrun simctl push booted com.urlxl.llama-Mail-for-Mac payload.json`
        with `{"aps":{"alert":{"title":"Sign-in request"},"category":"MFA_CHALLENGE"},
        "type":"mfa_challenge","challengeId":"test-1"}`
- [ ] Contact add/edit/delete → syncs to server; server edits flow back
- [ ] Theme switching: all 13 themes apply across inbox/detail/settings
- [ ] Pull mode background: iOS BGAppRefresh fires (~15 min, device only);
      macOS resumes polling after sleep/wake
- [ ] Manual IMAP mode shows the "not supported in v1" guidance (ponytail)

## Release steps (human/infra)

1. **Fonts (ponytail)**: add Space Grotesk + IBM Plex Mono TTFs to the bundle;
   `AppFont` picks them up by name automatically.
2. **APNs key**: upload the .p8 auth key to the backend push service; confirm
   `aps-environment` flips to `production` in the distribution profile.
3. **Archive**: Xcode → Product → Archive
   - iOS: distribute via TestFlight / App Store Connect
   - macOS: Developer ID signing + notarization, or Mac App Store
4. **Localization**: `Localizable.xcstrings` is in place; export for
   translation once the Android `strings.xml` keys are provided.
5. Re-run this checklist on release candidates for both platforms.
