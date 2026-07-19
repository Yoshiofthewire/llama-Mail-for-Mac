# Pairing Auth: Query Params to Headers (Mac Client) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch every networking class in this app that sends pairing-auth
credentials (`subscriberId`/`subscriberHash`, held in `RelayAuth`) from
attaching them as `?sub=&hash=` URL query params to sending them as
`X-Kypost-Subscriber-Id`/`X-Kypost-Subscriber-Hash` HTTP headers, so the
credentials stop appearing in server access logs / reverse-proxy logs.
Mirrors the already-shipped Android and Linux client migrations.

**Architecture:** `RelayAuth` (`Data/Networking/HTTPClient.swift`) gains a
`headerFields: [String: String]` computed property alongside its existing
`queryItems: [URLQueryItem]`. `HTTPClient.get`/`getData`/`post` already
accept a `headers: [String: String] = [:]` parameter — no `HTTPClient`
changes needed at all. Every call site that currently passes
`auth.queryItems` as the `query:` argument switches to passing whatever
non-auth query items it still needs (often none, i.e. `[]`) as `query:` and
`auth.headerFields` as `headers:`. Once every call site is converted,
`queryItems` is deleted — a clean cutover, matching Android/Linux; the
server (already shipped) accepts both forms, so the client doesn't need to.

**Genuine architectural difference from the Android/Linux siblings — read
before starting:** on THIS client, `NativeRegistrationClient.swift`'s
`register()` call IS in scope. On Android/Linux/server, native registration
sends credentials in the POST body only, with no `sub`/`hash` query params
at all, because the subscriber hash doesn't exist until registration mints
it. On this Mac client, the pairing deep link / QR code
(`llamalabels://native-pair`) already carries `sub` **and** `hash` directly
as required params (see `DeepLinkHandler.swift`'s `PairingParams`) — the
hash is pre-computed server-side and baked into the QR code before
registration ever happens, so `register()` legitimately sends
`params.auth.queryItems` (sub+hash) as query params, and the JSON body
never carries `subscriberHash` at all. This is real, confirmed behavior,
not a bug — it means this plan has one more in-scope file than its Android
or Linux counterparts.

**Tech Stack:** Swift, Foundation (`URLSession`/`URLRequest`), Swift Testing
(`@Suite`/`@Test`/`#expect`, not XCTest). Tests use `stubClient(...)`
(`TestSupport.swift`), which constructs an `HTTPClient` via its injectable
`Transport` closure and hands each outgoing `URLRequest` to an `onRequest`
callback before returning a canned response — no real network calls, no
mocking framework.

## Global Constraints

- Test/build command: `xcodebuild test -scheme "llama Mail for Mac"
  -destination 'platform=macOS'` (per `AGENTS.md`'s Testing section) must
  succeed with zero failures. This repo's shared `.xctestplan` has both test
  targets set `parallelizable: false` — **do not** touch that setting; it's
  off because Swift Testing's in-process parallelism triggers a real,
  unrelated SwiftData/CoreData crash under concurrent `ModelContainer`
  usage in this suite (documented in `AGENTS.md`), not something this
  plan's changes should re-enable or work around.
- No new dependencies — `URLRequest.setValue(_:forHTTPHeaderField:)` is
  already used inside `HTTPClient.get/getData/post` for the `headers:`
  parameter; nothing new is needed.
- Header names are exactly `X-Kypost-Subscriber-Id` and
  `X-Kypost-Subscriber-Hash`, matching the server, Android, and Linux
  clients (already shipped).
- This is a clean cutover, not a dual-write: the client sends headers only,
  no `?sub=&hash=` fallback. The server accepts both (already shipped), so
  this is safe.
- Scope is exactly: `RelayAuth` in `HTTPClient.swift`, plus 5 files with
  real `auth.queryItems` call sites: `PgpQrClient.swift` (`fetchToken`
  only), `NativeRegistrationClient.swift` (`register` — see the
  architectural note above), `PushNotificationClient.swift` (`pull`),
  `ContactSyncClient.swift` (`pull`/`push`/`dedupe`/`fetchPhoto` — all 4
  methods live in this one file/class on this client, unlike Linux which
  splits photo fetch into a separate file), `RelayMailSource.swift` (6
  methods: `listFolders`, `fetchEmails`, `performAction` — shared by
  `move`/`delete`/`archive`/`markSpam`/`markRead` — `listAttachments`,
  `downloadAttachment`, `send`).
- Out of scope, do not touch: `PgpQrClient.fetchKey` and `PgpQrClient.keyURL(fromScannedPayload:)`
  (both use an unrelated single-use `t` token read from a pre-built/scanned
  URL, never `RelayAuth`), `MfaResponseClient.swift` (already sends
  `subscriberId`/`subscriberHash` in the JSON POST body only — confirmed,
  no `query:` argument passed to `httpClient.post` at all), `HTTPClient.swift`'s
  `get`/`getData`/`post` methods themselves (the `headers:` parameter this
  plan uses already exists and is already correct), and
  `DeepLinkHandler.swift` (parses *incoming* deep-link query items when a
  QR/link is scanned — unrelated to *outgoing* request auth).
- Every non-auth query param must survive unchanged: `PushNotificationClient.pull`'s
  unconditional `after` (always appended, even when the cursor is 0 — this
  differs from the Linux client, which omits `after` when the cursor is 0;
  preserve the Mac behavior exactly as it is, don't "fix" it to match
  Linux), `ContactSyncClient.pull`'s `since`, `RelayMailSource.listFolders`'s
  conditional `parent`, `fetchEmails`'s `limit`/`mailbox`/`since`,
  `listAttachments`'s `mailbox`/`messageId`, `downloadAttachment`'s
  `mailbox`/`messageId`/`index`.
- **Test-assertion trap, confirmed multiple times in this exact codebase —
  read this before touching any test file:** several endpoints have *no*
  non-auth query params at all. Once `sub`/`hash` move to headers, their
  query list becomes empty, and `HTTPClient.appending(queryOrThrow:)`
  returns the URL **unchanged** when the query array is empty (`guard
  !items.isEmpty else { return self }` — confirmed in `HTTPClient.swift`).
  That means any test asserting `url.hasPrefix(".../path?")` for one of
  these endpoints will start failing — the `?` disappears entirely. This
  affects tests you might not expect from a naive grep for `"sub="`/`"hash="`,
  because the assertion doesn't need to mention `sub`/`hash` literally to
  break — it just needs to check for a trailing `?`. Every task below that
  touches a no-other-query-param endpoint enumerates its own affected
  tests explicitly, including tests in files one layer above the direct
  client (repository/service-level tests that exercise the same client
  indirectly) — this was found the hard way during the Linux client's
  equivalent migration and confirmed again here by grepping the *entire*
  test suite for `hasPrefix("...?")`/exact-URL-equality patterns, not just
  `sub=`/`hash=` substrings. Do not skip a task's listed test files under
  the assumption "only the obvious one needs updating."

---

### Task 1: `RelayAuth.headerFields` + its own test

**Files:**
- Modify: `Data/Networking/HTTPClient.swift`
- Test: `Tests/NetworkingTests.swift` (append a new `@Suite`)

*(Paths above are relative to `llama Mail for Mac/`, this repo's source
root — the actual paths are `llama Mail for Mac/Data/Networking/HTTPClient.swift`
and `llama Mail for MacTests/NetworkingTests.swift`.)*

**Interfaces:**
- Consumes: nothing new.
- Produces: `RelayAuth.headerFields: [String: String]`, returning
  `["X-Kypost-Subscriber-Id": sub, "X-Kypost-Subscriber-Hash": hash]`.
  Tasks 2–6 each pass this as the `headers:` argument to
  `HTTPClient.get/getData/post`. `queryItems` is left in place for now —
  removed in Task 7 once nothing calls it.

- [ ] **Step 1: Write the failing test**

Append to the end of `llama Mail for MacTests/NetworkingTests.swift` (after
the closing brace of `ContactSyncClientTests`):

```swift
@Suite struct RelayAuthTests {
    @Test func headerFieldsReturnsSubscriberIdAndHashAsNamedHeaders() {
        let auth = RelayAuth(sub: "sub-1", hash: "hash-1")

        let fields = auth.headerFields

        #expect(fields == [
            "X-Kypost-Subscriber-Id": "sub-1",
            "X-Kypost-Subscriber-Hash": "hash-1",
        ])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS' -only-testing:llama_Mail_for_MacTests/NetworkingTests/RelayAuthTests`
(if `-only-testing` with this identifier doesn't resolve in this Xcode
version, fall back to the full suite: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS'`)
Expected: FAIL to compile — `headerFields` is undefined on `RelayAuth`.

- [ ] **Step 3: Write the implementation**

In `llama Mail for Mac/Data/Networking/HTTPClient.swift`, replace:
```swift
/// Relay auth credentials, sent as query params on every request (spec §2).
struct RelayAuth: Equatable, Sendable {
    var sub: String
    var hash: String

    init(sub: String, hash: String) {
        self.sub = sub
        self.hash = hash
    }

    init(pairing: Pairing) {
        self.init(sub: pairing.sub, hash: pairing.hash)
    }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "sub", value: sub), URLQueryItem(name: "hash", value: hash)]
    }
}
```
with:
```swift
/// Relay auth credentials. headerFields sends them as
/// X-Kypost-Subscriber-Id/X-Kypost-Subscriber-Hash headers -- the form
/// every Relay call site is migrating to (server already accepts both,
/// headers preferred). queryItems (legacy ?sub=&hash= query params) is
/// being phased out call site by call site and deleted once nothing uses
/// it anymore.
struct RelayAuth: Equatable, Sendable {
    var sub: String
    var hash: String

    init(sub: String, hash: String) {
        self.sub = sub
        self.hash = hash
    }

    init(pairing: Pairing) {
        self.init(sub: pairing.sub, hash: pairing.hash)
    }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "sub", value: sub), URLQueryItem(name: "hash", value: hash)]
    }

    var headerFields: [String: String] {
        ["X-Kypost-Subscriber-Id": sub, "X-Kypost-Subscriber-Hash": hash]
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "llama Mail for Mac/Data/Networking/HTTPClient.swift" "llama Mail for MacTests/NetworkingTests.swift"
git commit -m "net: add RelayAuth.headerFields for the pairing-auth header migration"
```

---

### Task 2: `PgpQrClient.swift` — `fetchToken` switches to headers

**Files:**
- Modify: `llama Mail for Mac/Data/Networking/PgpQrClient.swift`
- Test: `llama Mail for MacTests/PgpQrTests.swift`

**Interfaces:**
- Consumes: `RelayAuth.headerFields` from Task 1.
- Produces: no interface change. `fetchToken`'s signature is unchanged.
  `fetchKey` and `keyURL(fromScannedPayload:)` are untouched (out of scope
  — unrelated `t`-token mechanism).

- [ ] **Step 1: Write the failing test**

In `llama Mail for MacTests/PgpQrTests.swift`, find the test
`fetchTokenSendsPairingAuthToTheTokenEndpoint` (around line 36) and replace
its body:
```swift
@Test func fetchTokenSendsPairingAuthToTheTokenEndpoint() async throws {
    let capture = Box<URLRequest?>(nil)
    let client = PgpQrClient(httpClient: stubClient(json: tokenJSON) { capture.value = $0 })

    _ = try await client.fetchToken(
        serverUrl: "https://mail.example.com",
        auth: RelayAuth(sub: "u1", hash: "h1")
    )

    let request = try #require(capture.value)
    // Pairing auth now travels as headers, not query params (server prefers
    // headers; the app has no web session cookie either way).
    #expect(request.url?.absoluteString == "https://mail.example.com/api/pgp/qr/token")
    #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
    #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
    #expect(request.httpMethod == "GET")
}
```
(The URL loses its `?sub=u1&hash=h1` suffix entirely — `fetchToken` has no
other query params, so `HTTPClient.appending(queryOrThrow:)` returns the
bare URL once the query list is empty.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS' -only-testing:llama_Mail_for_MacTests/PgpQrTests`
(fall back to the full suite if `-only-testing` doesn't resolve)
Expected: FAIL — headers absent, URL still has the old query string.

- [ ] **Step 3: Rewrite the production code**

In `llama Mail for Mac/Data/Networking/PgpQrClient.swift`, replace `fetchToken`'s
body:
```swift
        return try await httpClient.get(
            PgpQrTokenResponse.self,
            url: base.appending(path: "api/pgp/qr/token"),
            query: auth.queryItems
        )
```
with:
```swift
        return try await httpClient.get(
            PgpQrTokenResponse.self,
            url: base.appending(path: "api/pgp/qr/token"),
            headers: auth.headerFields
        )
```

Update `fetchToken`'s doc comment (currently references `?sub&hash` and
"the backend accepts sub/hash query params precisely because paired native
clients have no web session cookie") to describe header-based auth instead
— e.g. change `GET {srv}/api/pgp/qr/token?sub&hash` to `GET
{srv}/api/pgp/qr/token` and "the backend accepts sub/hash query params" to
"the backend accepts X-Kypost-Subscriber-Id/X-Kypost-Subscriber-Hash
headers". Leave the file's top-of-file header comment's `Mint: GET
{srv}/api/pgp/qr/token` line and the `fetchKey`/`keyURL` doc comments
untouched (they don't reference `sub`/`hash` query params in a way this
change affects, or are about the unrelated `t`-token path).

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2.
Expected: PASS (including the untouched `fetchKey`/`keyURL` tests).

- [ ] **Step 5: Commit**

```bash
git add "llama Mail for Mac/Data/Networking/PgpQrClient.swift" "llama Mail for MacTests/PgpQrTests.swift"
git commit -m "net: send pairing auth as headers in PgpQrClient.fetchToken"
```

---

### Task 3: `NativeRegistrationClient.swift` — `register` switches to headers

This is the one file in scope on this client that ISN'T in scope on
Android/Linux — see the Global Constraints architectural note. Two
separate test files exercise this call, at two different layers (a direct
client-level test in `NetworkingTests.swift`, and a
`DeviceRegistrationService`-level test in `PushTests.swift` that goes
through the same client indirectly) — both need updating, matching this
plan's test-assertion-trap warning.

**Files:**
- Modify: `llama Mail for Mac/Data/Networking/NativeRegistrationClient.swift`
- Test: `llama Mail for MacTests/NetworkingTests.swift`
- Test: `llama Mail for MacTests/PushTests.swift`

**Interfaces:**
- Consumes: `RelayAuth.headerFields` from Task 1 (via `params.auth`).
- Produces: no interface change.

- [ ] **Step 1: Write the failing tests**

In `llama Mail for MacTests/NetworkingTests.swift`, inside
`NativeRegistrationClientTests`, find `successCarriesResponseAndAuthQuery`
and replace its body:
```swift
    @Test func successCarriesResponseAndAuthQuery() async {
        let client = stubClient(status: 200, json: #"{"ok": true, "deviceId": "d1"}"#) { request in
            let url = request.url!.absoluteString
            #expect(url == "https://relay.example.com/api/notifications/native/register")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
            #expect(request.httpMethod == "POST")
            // Body fields are a binding contract with the live backend:
            // subscriberId, pairingToken, and deviceToken are required.
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""subscriberId":"u1""#))
            #expect(body.contains(#""pairingToken":"p1""#))
            #expect(body.contains(#""deviceToken":"apns-token""#))
            // deviceName is what the server's paired-device list displays;
            // without it the UI falls back to the platform string.
            #expect(body.contains(#""deviceName":""#))
        }
        let outcome = await NativeRegistrationClient(httpClient: client)
            .register(deviceToken: "apns-token", params: params)
        guard case .success(let response) = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
        #expect(response.deviceId == "d1")
    }
```
(The URL loses its `?sub=&hash=` suffix entirely — `register` has no other
query params.)

(Do not rename the test — you may keep `successCarriesResponseAndAuthQuery`
as its name even though auth no longer travels as a query param; renaming
is optional polish, not required.)

In `llama Mail for MacTests/PushTests.swift`, inside
`DeviceRegistrationServiceTests`, find `reregisterUsesStoredPairing` and
replace its body:
```swift
    @Test func reregisterUsesStoredPairing() async throws {
        let client = stubClient(json: #"{"ok": true, "deviceId": "dev-8"}"#) { request in
            #expect(
                request.url!.absoluteString
                    == "\(server)/api/notifications/native/register"
            )
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
        }
        let env = try makeEnvironment(client: client, paired: true)
        let outcome = await env.service.reregisterIfPaired(deviceToken: "t2")
        #expect(outcome != nil)
        #expect(try env.pairingStore.loadPairing()?.lastDeviceId == "dev-8")
    }
```
(This test constructs its `RelayAuth` indirectly via the stored pairing,
built by this file's private `makePairing()` helper — confirmed to set
`sub: "u1", hash: "h1"` — so the two expected header values above are
correct as written.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS' -only-testing:llama_Mail_for_MacTests/NetworkingTests/NativeRegistrationClientTests -only-testing:llama_Mail_for_MacTests/PushTests/DeviceRegistrationServiceTests`
(fall back to the full suite if `-only-testing` doesn't resolve)
Expected: both FAIL — headers absent, URLs still carry the old query
string.

- [ ] **Step 3: Rewrite the production code**

In `llama Mail for Mac/Data/Networking/NativeRegistrationClient.swift`, replace:
```swift
            let response = try await httpClient.post(
                RegistrationResponse.self,
                url: endpoint,
                query: params.auth.queryItems,
                jsonBody: RegisterRequest(
```
with:
```swift
            let response = try await httpClient.post(
                RegistrationResponse.self,
                url: endpoint,
                headers: params.auth.headerFields,
                jsonBody: RegisterRequest(
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same commands as Step 2.
Expected: PASS (both suites, including the other
`NativeRegistrationClientTests`/`DeviceRegistrationServiceTests` tests that
don't touch auth transport, e.g. `unauthorizedPromptsRescan`,
`initialPairingOmitsDeviceId`).

- [ ] **Step 5: Commit**

```bash
git add "llama Mail for Mac/Data/Networking/NativeRegistrationClient.swift" "llama Mail for MacTests/NetworkingTests.swift" "llama Mail for MacTests/PushTests.swift"
git commit -m "net: send pairing auth as headers in NativeRegistrationClient.register"
```

---

### Task 4: `PushNotificationClient.swift` — `pull` switches to headers

**Files:**
- Modify: `llama Mail for Mac/Data/Networking/PushNotificationClient.swift`
- Test: `llama Mail for MacTests/PushTests.swift`

**Interfaces:**
- Consumes: `RelayAuth.headerFields` from Task 1.
- Produces: no interface change. The `after` query param is unconditional
  on this client (always appended, even for cursor 0) and is unaffected by
  this change — it stays a query param, so `pull`'s URL always retains a
  `?` regardless of this migration.

- [ ] **Step 1: Write the failing test**

In `llama Mail for MacTests/PushTests.swift`, inside `PushRepositoryTests`,
find `pullDeduplicatesBySeqAndAdvancesCursorAfterHandoff` and replace its
`onRequest` closure body:
```swift
        let client = stubClient(json: json) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("\(server)/api/notifications/native/pull?"))
            #expect(url.contains("after=3"))
            #expect(!url.contains("sub="))
            #expect(!url.contains("hash="))
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") != nil)
        }
```
(`after=3` and the `?` prefix are unaffected and must keep passing — only
`sub=`/`hash=` disappear from the URL, replaced by headers. Do not modify
`storedPullEndpointOverridesDerivedOne` — it doesn't assert on `sub=`/`hash=`
or headers at all, only the endpoint-override behavior, and its `?`-prefix
check stays valid since `after=0` is still unconditionally appended.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS' -only-testing:llama_Mail_for_MacTests/PushTests/PushRepositoryTests`
(fall back to the full suite if `-only-testing` doesn't resolve)
Expected: FAIL — headers absent (`X-Kypost-Subscriber-Id` is nil), `sub=`/`hash=`
still present in the URL.

- [ ] **Step 3: Rewrite the production code**

In `llama Mail for Mac/Data/Networking/PushNotificationClient.swift`, replace
`pull`'s body:
```swift
    func pull(endpoint: URL, auth: RelayAuth, after cursor: Int) async throws -> PullResponse {
        try await httpClient.get(
            PullResponse.self,
            url: endpoint,
            query: auth.queryItems + [URLQueryItem(name: "after", value: String(cursor))]
        )
    }
```
with:
```swift
    func pull(endpoint: URL, auth: RelayAuth, after cursor: Int) async throws -> PullResponse {
        try await httpClient.get(
            PullResponse.self,
            url: endpoint,
            query: [URLQueryItem(name: "after", value: String(cursor))],
            headers: auth.headerFields
        )
    }
```

Update the doc comment above `pull` (currently `/// GET
{pullEndpoint}?sub=&hash=&after={cursor}`) to `/// GET
{pullEndpoint}?after={cursor}, with pairing auth as headers`.

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2.
Expected: PASS (including `storedPullEndpointOverridesDerivedOne`,
unaffected).

- [ ] **Step 5: Commit**

```bash
git add "llama Mail for Mac/Data/Networking/PushNotificationClient.swift" "llama Mail for MacTests/PushTests.swift"
git commit -m "net: send pairing auth as headers in PushNotificationClient.pull"
```

---

### Task 5: `ContactSyncClient.swift` — all 4 methods switch to headers

This file bundles `pull`, `push`, `dedupe`, **and** `fetchPhoto` in one
class — unlike Linux, which splits photo fetch into a separate
`ContactPhotoClient`. Tests are split across two files: direct
client-level tests for `pull`/`push` in `NetworkingTests.swift`, and
repository-level tests for `dedupe`/a `push`-driving sync flow in
`ContactSyncTests.swift`. `fetchPhoto` has **zero** existing test coverage
anywhere in the suite — this task adds a new test for it.

**Files:**
- Modify: `llama Mail for Mac/Data/Networking/ContactSyncClient.swift`
- Test: `llama Mail for MacTests/NetworkingTests.swift`
- Test: `llama Mail for MacTests/ContactSyncTests.swift`

**Interfaces:**
- Consumes: `RelayAuth.headerFields` from Task 1.
- Produces: no interface change. `pull`'s `since` query param is
  unaffected.

- [ ] **Step 1: Write the failing tests**

In `llama Mail for MacTests/NetworkingTests.swift`, inside
`ContactSyncClientTests`, update `pullSendsSinceAndDecodesResponse`'s
`onRequest` closure — add header assertions alongside the existing
`since=123` check (which stays, `pull` still has that one non-auth query
param):
```swift
        let client = stubClient(
            status: 200,
            json: #"{"cursor": 456, "changed": [{"uid": "srv-1", "rev": 2, "fn": "Ada"}], "deleted": []}"#
        ) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("https://relay.example.com/api/contacts/sync"))
            #expect(url.contains("since=123"))
            #expect(!url.contains("sub="))
            #expect(!url.contains("hash="))
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h")
            #expect(request.httpMethod == "GET")
        }
```

Update `pushSendsBaseCursorAndChanges`'s `onRequest` closure — `push` has
no other query params, so its URL loses the `?` entirely:
```swift
        let client = stubClient(status: 200, json: #"{"cursor": 7}"#) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://relay.example.com/api/contacts/sync")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""baseCursor":123"#))
            #expect(body.contains(#""fn":"Ada""#))
            #expect(body.contains(#""value":"ada@example.com""#))
        }
```

In `llama Mail for MacTests/ContactSyncTests.swift`, inside
`ContactSyncRepositoryTests`, update `fullSyncAssignsUidWithoutDuplicating`
(this drives a `push` through the repository — its URL also loses the `?`
entirely):
```swift
        let client = stubClient(json: json) { request in
            #expect(
                request.url!.absoluteString == "https://relay.example.com/api/contacts/sync"
            )
            // Queued local changes go out as a push (POST {baseCursor, changes});
            // creates carry an empty uid (Android contract).
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""baseCursor":0"#))
            #expect(body.contains(#""fn":"Ada""#))
            #expect(body.contains(#""uid":"""#))
        }
```

Update `dedupeSendsEmptyJSONBodyToTheDedupeEndpoint` (`dedupe` also has no
other query params):
```swift
@Test func dedupeSendsEmptyJSONBodyToTheDedupeEndpoint() async throws {
    let client = stubClient(json: #"{"mergedCount": 0, "groups": []}"#) { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://relay.example.com/api/contacts/dedupe")
        #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
        #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
        // The backend never reads the body, but does expect valid JSON.
        let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
        #expect(body == "{}")
    }
    let env = try makeEnvironment(client: client)
    let report = try await env.repository.dedupe()
    #expect(report == ContactDedupeReport(mergedCount: 0, groups: []))
}
```

Add a new test for `fetchPhoto` (no existing coverage) — place it inside
`ContactSyncClientTests` in `NetworkingTests.swift`, alongside
`pullSendsSinceAndDecodesResponse`/`pushSendsBaseCursorAndChanges`:
```swift
    @Test func fetchPhotoSendsPairingAuthAsHeaders() async throws {
        let client = stubClient(status: 200, json: "photo-bytes") { request in
            #expect(request.httpMethod == "GET")
            #expect(
                request.url?.absoluteString
                    == "https://relay.example.com/api/contacts/c-1/photo"
            )
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h")
        }
        let data = try await ContactSyncClient(httpClient: client).fetchPhoto(
            serverUrl: "https://relay.example.com",
            auth: RelayAuth(sub: "u", hash: "h"),
            uid: "c-1"
        )
        #expect(String(decoding: data, as: UTF8.self) == "photo-bytes")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS' -only-testing:llama_Mail_for_MacTests/NetworkingTests/ContactSyncClientTests -only-testing:llama_Mail_for_MacTests/ContactSyncTests/ContactSyncRepositoryTests`
(fall back to the full suite if `-only-testing` doesn't resolve)
Expected: `pullSendsSinceAndDecodesResponse`, `pushSendsBaseCursorAndChanges`,
`fullSyncAssignsUidWithoutDuplicating`, `dedupeSendsEmptyJSONBodyToTheDedupeEndpoint`
FAIL (headers absent); `fetchPhotoSendsPairingAuthAsHeaders` FAILS to
compile (`fetchPhoto` doesn't send headers yet — the assertions on it will
fail at runtime once it compiles against the current production code, but
the test itself is new so confirm it fails for the right reason: headers
nil, URL still has `?sub=&hash=`).

- [ ] **Step 3: Rewrite the production code**

In `llama Mail for Mac/Data/Networking/ContactSyncClient.swift`, replace `pull`'s
body:
```swift
        try await httpClient.get(
            ContactSyncPullResponse.self,
            url: try endpoint(serverUrl),
            query: auth.queryItems + [
                URLQueryItem(name: "since", value: String(max(since, 0)))
            ]
        )
```
with:
```swift
        try await httpClient.get(
            ContactSyncPullResponse.self,
            url: try endpoint(serverUrl),
            query: [URLQueryItem(name: "since", value: String(max(since, 0)))],
            headers: auth.headerFields
        )
```

Replace `push`'s body:
```swift
        try await httpClient.post(
            ContactSyncPullResponse.self,
            url: try endpoint(serverUrl),
            query: auth.queryItems,
            jsonBody: ContactSyncPushRequest(baseCursor: baseCursor, changes: changes)
        )
```
with:
```swift
        try await httpClient.post(
            ContactSyncPullResponse.self,
            url: try endpoint(serverUrl),
            headers: auth.headerFields,
            jsonBody: ContactSyncPushRequest(baseCursor: baseCursor, changes: changes)
        )
```

Replace `dedupe`'s body:
```swift
        return try await httpClient.post(
            ContactDedupeReport.self,
            url: base.appending(path: "api/contacts/dedupe"),
            query: auth.queryItems,
            jsonBody: EmptyJSONBody()
        )
```
with:
```swift
        return try await httpClient.post(
            ContactDedupeReport.self,
            url: base.appending(path: "api/contacts/dedupe"),
            headers: auth.headerFields,
            jsonBody: EmptyJSONBody()
        )
```

Replace `fetchPhoto`'s body:
```swift
        return try await httpClient.getData(
            url: base.appending(path: "api/contacts/\(uid)/photo"),
            query: auth.queryItems
        )
```
with:
```swift
        return try await httpClient.getData(
            url: base.appending(path: "api/contacts/\(uid)/photo"),
            headers: auth.headerFields
        )
```

Update the file's top-of-file doc comment (currently `Pull: GET
{srv}/api/contacts/sync?sub&hash&since=N` / `Push: POST
{srv}/api/contacts/sync?sub&hash`) and `dedupe`'s/`fetchPhoto`'s doc
comments (currently `POST {srv}/api/contacts/dedupe?sub&hash` / `GET
{srv}/api/contacts/{uid}/photo?sub&hash`) to describe header-based auth.

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (all tests, including the new `fetchPhotoSendsPairingAuthAsHeaders`
and every other pre-existing test in both suites that doesn't touch auth
transport).

- [ ] **Step 5: Commit**

```bash
git add "llama Mail for Mac/Data/Networking/ContactSyncClient.swift" "llama Mail for MacTests/NetworkingTests.swift" "llama Mail for MacTests/ContactSyncTests.swift"
git commit -m "net: send pairing auth as headers in ContactSyncClient (pull/push/dedupe/fetchPhoto)"
```

---

### Task 6: `RelayMailSource.swift` — all 6 methods switch to headers

The largest task: `listFolders`, `fetchEmails`, `performAction` (shared by
5 public verbs), `listAttachments`, `downloadAttachment`, `send`.
`performAction` alone is exercised by **3 separate test functions**
(`movePostsBulkActionBody`, `deletePostsBulkActionBodyWithoutTarget`, and
the parameterized `actionVerbsPostBulkActionBody` covering
archive/spam/read) — all 3 need the same fix, matching this plan's
test-assertion-trap warning; missing any one of them would leave the suite
red.

**Files:**
- Modify: `llama Mail for Mac/Data/Mail/RelayMailSource.swift`
- Test: `llama Mail for MacTests/MailTests.swift`

**Interfaces:**
- Consumes: `RelayAuth.headerFields` from Task 1.
- Produces: no interface change. Every non-auth query param
  (`listFolders`'s conditional `parent`, `fetchEmails`'s
  `limit`/`mailbox`/`since`, `listAttachments`'s `mailbox`/`messageId`,
  `downloadAttachment`'s `mailbox`/`messageId`/`index`) is unaffected.

- [ ] **Step 1: Write the failing tests**

In `llama Mail for MacTests/MailTests.swift`, update
`listFoldersMapsPathAndSearchIsLocalOnly`'s first `onRequest` closure (the
parent-less case — this one loses its `?` entirely, since `listFolders`
has no other query params when no `parent` is given) and add header
assertions to the with-parent case too:
```swift
    @Test func listFoldersMapsPathAndSearchIsLocalOnly() async throws {
        let json = #"{"parent": "", "folders": [{"path": "INBOX"}, {"path": "Archive", "deletable": true}]}"#
        let foldersClient = stubClient(json: json) { request in
            let url = request.url!.absoluteString
            #expect(url == "\(server)/api/inbox/folders")
            #expect(!url.contains("parent="))
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
        }
        let folders = try await RelayMailSource(httpClient: foldersClient, serverUrl: server, auth: auth)
            .listFolders()
        #expect(folders.map(\.name) == ["INBOX", "Archive"])

        // Subfolder listing scopes the request with the parent param.
        let subJson = #"{"parent": "Archive", "folders": [{"path": "Archive/Receipts", "deletable": true}]}"#
        let subClient = stubClient(json: subJson) { request in
            #expect(request.url!.absoluteString.contains("parent=Archive"))
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
        }
        let subs = try await RelayMailSource(httpClient: subClient, serverUrl: server, auth: auth)
            .listFolders(parent: "Archive")
        #expect(subs.map(\.name) == ["Archive/Receipts"])

        // The relay has no search endpoint; inbox search uses the local cache.
        await #expect(throws: MailSourceError.unsupported) {
            _ = try await RelayMailSource(httpClient: stubClient(), serverUrl: server, auth: auth)
                .search(folder: "INBOX", query: "report")
        }
    }
```

Update `fetchEmailsMapsByTabResponse`'s `onRequest` closure (keeps its `?`
— `limit`/`mailbox`/`since` remain):
```swift
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("\(server)/api/inbox?"))
            #expect(!url.contains("sub="))
            #expect(!url.contains("hash="))
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
```
(Keep the rest of that closure — the `mailbox=`/`limit=`/`since=` checks —
unchanged; only replace the `sub=`/`hash=` lines shown above.)

Update `movePostsBulkActionBody`'s `onRequest` closure (loses its `?`
entirely — `performAction` has no other query params):
```swift
    @Test func movePostsBulkActionBody() async throws {
        let client = stubClient(json: #"{"ok": true}"#) { request in
            #expect(request.url!.absoluteString == "\(server)/api/inbox/actions")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""action":"move""#))
            #expect(body.contains(#""messageIds":["e-1","e-2"]"#))
            #expect(body.contains(#""mailbox":"INBOX""#))
            #expect(body.contains(#""targetMailbox":"Archive\/2026""#))
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        try await source.move(messageIds: ["e-1", "e-2"], from: "INBOX", to: "Archive/2026")
    }
```

Update `deletePostsBulkActionBodyWithoutTarget`'s `onRequest` closure (same
fix):
```swift
    @Test func deletePostsBulkActionBodyWithoutTarget() async throws {
        let client = stubClient(json: #"{"ok": true}"#) { request in
            #expect(request.url!.absoluteString == "\(server)/api/inbox/actions")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""action":"delete""#))
            #expect(body.contains(#""messageIds":["e-1","e-2"]"#))
            #expect(body.contains(#""mailbox":"Trash""#))
            // targetMailbox is move-only; nil must be omitted, not null.
            #expect(!body.contains("targetMailbox"))
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        try await source.delete(messageIds: ["e-1", "e-2"], mailbox: "Trash")
    }
```

Update the parameterized `actionVerbsPostBulkActionBody`'s `onRequest`
closure (same fix, covers archive/spam/read):
```swift
    func actionVerbsPostBulkActionBody(
        verb: String,
        call: @Sendable (RelayMailSource) async throws -> Void
    ) async throws {
        let client = stubClient(json: #"{"ok": true}"#) { request in
            #expect(request.url!.absoluteString == "\(server)/api/inbox/actions")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""action":"\#(verb)""#))
            #expect(body.contains(#""messageIds":["e-1"]"#))
            #expect(body.contains(#""mailbox":"INBOX""#))
            #expect(!body.contains("targetMailbox"))
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        try await call(source)
    }
```

Update `sendPostsCommaStringBody`'s `onRequest` closure (loses its `?`
entirely — `send` has no other query params):
```swift
    @Test func sendPostsCommaStringBody() async throws {
        let client = stubClient(json: #"{"ok": true, "sentSaved": true}"#) { request in
            #expect(request.url!.absoluteString == "\(server)/api/mail/send")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""to":"a@x.com, b@x.com""#))
            #expect(body.contains(#""mode":"plain""#))
            // No attachments → the key is omitted entirely, not null/[].
            #expect(!body.contains("attachments"))
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        try await source.send(email: makeOutgoing())
    }
```

Update `listAttachmentsMapsMetadata`'s `onRequest` closure (keeps its `?`
— `mailbox`/`messageId` remain):
```swift
    @Test func listAttachmentsMapsMetadata() async throws {
        let json = #"{"ok": true, "attachments": [{"index": 0, "name": "report.pdf", "mimeType": "application/pdf", "size": 1234}, {"index": 1}]}"#
        let client = stubClient(json: json) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("\(server)/api/mail/attachments?"))
            #expect(url.contains("mailbox=INBOX"))
            #expect(url.contains("messageId=42"))
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        let attachments = try await source.listAttachments(folder: "INBOX", messageId: "42")

        #expect(attachments.count == 2)
        #expect(attachments[0] == EmailAttachment(
            index: 0, name: "report.pdf", mimeType: "application/pdf", size: 1234
        ))
        // Missing fields get safe fallbacks.
        #expect(attachments[1] == EmailAttachment(
            index: 1, name: "attachment", mimeType: "application/octet-stream", size: 0
        ))
    }
```

Update `downloadAttachmentReturnsRawBytes`'s `onRequest` closure (keeps its
`?` — `mailbox`/`messageId`/`index` remain):
```swift
    @Test func downloadAttachmentReturnsRawBytes() async throws {
        let client = stubClient(json: "raw-bytes") { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("\(server)/api/mail/attachment?"))
            #expect(url.contains("messageId=42"))
            #expect(url.contains("index=1"))
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Id") == "u1")
            #expect(request.value(forHTTPHeaderField: "X-Kypost-Subscriber-Hash") == "h1")
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        let data = try await source.downloadAttachment(folder: "INBOX", messageId: "42", index: 1)
        #expect(String(decoding: data, as: UTF8.self) == "raw-bytes")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS' -only-testing:llama_Mail_for_MacTests/MailTests`
(fall back to the full suite if `-only-testing` doesn't resolve)
Expected: all 8 touched tests FAIL (headers absent from the
still-unconverted production code); other tests in this file (rich-text
HTML, error mapping, tab computation, send-use-case validation) are
unaffected.

- [ ] **Step 3: Rewrite the production code**

In `llama Mail for Mac/Data/Mail/RelayMailSource.swift`, replace `listFolders`'s
body:
```swift
    func listFolders(parent: String?) async throws -> [MailFolder] {
        var query = auth.queryItems
        if let parent, !parent.isEmpty {
            query.append(URLQueryItem(name: "parent", value: parent))
        }
        let response = try await httpClient.get(
            RelayFolderListResponse.self,
            url: try endpoint("api/inbox/folders"),
            query: query
        )
        return (response.folders ?? []).map { MailFolder(name: $0.path) }
    }
```
with:
```swift
    func listFolders(parent: String?) async throws -> [MailFolder] {
        var query: [URLQueryItem] = []
        if let parent, !parent.isEmpty {
            query.append(URLQueryItem(name: "parent", value: parent))
        }
        let response = try await httpClient.get(
            RelayFolderListResponse.self,
            url: try endpoint("api/inbox/folders"),
            query: query,
            headers: auth.headerFields
        )
        return (response.folders ?? []).map { MailFolder(name: $0.path) }
    }
```

Replace `fetchEmails`'s body:
```swift
        let response = try await httpClient.get(
            RelayInboxResponse.self,
            url: try endpoint("api/inbox"),
            query: auth.queryItems + [
                URLQueryItem(name: "limit", value: String(max(to, 1))),
                URLQueryItem(name: "mailbox", value: folder),
                URLQueryItem(name: "since", value: "0"),
            ]
        )
```
with:
```swift
        let response = try await httpClient.get(
            RelayInboxResponse.self,
            url: try endpoint("api/inbox"),
            query: [
                URLQueryItem(name: "limit", value: String(max(to, 1))),
                URLQueryItem(name: "mailbox", value: folder),
                URLQueryItem(name: "since", value: "0"),
            ],
            headers: auth.headerFields
        )
```

Replace `performAction`'s body:
```swift
        _ = try await httpClient.post(
            RelayActionResponse.self,
            url: try endpoint("api/inbox/actions"),
            query: auth.queryItems,
            jsonBody: RelayActionRequest(
```
with:
```swift
        _ = try await httpClient.post(
            RelayActionResponse.self,
            url: try endpoint("api/inbox/actions"),
            headers: auth.headerFields,
            jsonBody: RelayActionRequest(
```

Replace `listAttachments`'s body:
```swift
        let response = try await httpClient.get(
            RelayAttachmentListResponse.self,
            url: try endpoint("api/mail/attachments"),
            query: auth.queryItems + [
                URLQueryItem(name: "mailbox", value: folder),
                URLQueryItem(name: "messageId", value: messageId),
            ]
        )
```
with:
```swift
        let response = try await httpClient.get(
            RelayAttachmentListResponse.self,
            url: try endpoint("api/mail/attachments"),
            query: [
                URLQueryItem(name: "mailbox", value: folder),
                URLQueryItem(name: "messageId", value: messageId),
            ],
            headers: auth.headerFields
        )
```

Replace `downloadAttachment`'s body:
```swift
        try await httpClient.getData(
            url: try endpoint("api/mail/attachment"),
            query: auth.queryItems + [
                URLQueryItem(name: "mailbox", value: folder),
                URLQueryItem(name: "messageId", value: messageId),
                URLQueryItem(name: "index", value: String(index)),
            ]
        )
```
with:
```swift
        try await httpClient.getData(
            url: try endpoint("api/mail/attachment"),
            query: [
                URLQueryItem(name: "mailbox", value: folder),
                URLQueryItem(name: "messageId", value: messageId),
                URLQueryItem(name: "index", value: String(index)),
            ],
            headers: auth.headerFields
        )
```

Replace `send`'s body:
```swift
        _ = try await httpClient.post(
            RelaySendResponse.self,
            url: try endpoint("api/mail/send"),
            query: auth.queryItems,
            jsonBody: RelaySendRequest(from: email)
        )
```
with:
```swift
        _ = try await httpClient.post(
            RelaySendResponse.self,
            url: try endpoint("api/mail/send"),
            headers: auth.headerFields,
            jsonBody: RelaySendRequest(from: email)
        )
```

Update the file's top-of-file doc comment (currently lists `GET
/api/inbox?sub&hash&limit&mailbox&since`, `GET
/api/inbox/folders?sub&hash`, `POST /api/mail/send?sub&hash`) to describe
header-based auth instead.

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add "llama Mail for Mac/Data/Mail/RelayMailSource.swift" "llama Mail for MacTests/MailTests.swift"
git commit -m "net: send pairing auth as headers in RelayMailSource (all 6 endpoints)"
```

---

### Task 7: Delete `RelayAuth.queryItems`

By this point every call site in the codebase uses `headerFields` instead.
`queryItems` is now dead code.

**Files:**
- Modify: `llama Mail for Mac/Data/Networking/HTTPClient.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing — this only removes an unused property and tidies the
  doc comment. No call site anywhere in the codebase references
  `queryItems` after this task (verified in Step 1 below).

- [ ] **Step 1: Confirm nothing still calls `queryItems`**

Run: `grep -rn "\.queryItems\b" --include='*.swift' . | grep -v -i "DerivedData\|/build/"`
Expected: exactly one match — the definition in `HTTPClient.swift` itself
(`var queryItems: [URLQueryItem] { ... }`). Any other match (besides
`HTTPClient.swift:161`'s unrelated `components.queryItems` and
`DeepLinkHandler.swift`'s unrelated incoming-URL parsing, both pre-existing
and never touched by this plan) means a call site was missed in Tasks 2–6
and must be fixed before proceeding.

- [ ] **Step 2: Remove `queryItems` and tidy the doc comment**

In `llama Mail for Mac/Data/Networking/HTTPClient.swift`, replace:
```swift
/// Relay auth credentials. headerFields sends them as
/// X-Kypost-Subscriber-Id/X-Kypost-Subscriber-Hash headers -- the form
/// every Relay call site is migrating to (server already accepts both,
/// headers preferred). queryItems (legacy ?sub=&hash= query params) is
/// being phased out call site by call site and deleted once nothing uses
/// it anymore.
struct RelayAuth: Equatable, Sendable {
    var sub: String
    var hash: String

    init(sub: String, hash: String) {
        self.sub = sub
        self.hash = hash
    }

    init(pairing: Pairing) {
        self.init(sub: pairing.sub, hash: pairing.hash)
    }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "sub", value: sub), URLQueryItem(name: "hash", value: hash)]
    }

    var headerFields: [String: String] {
        ["X-Kypost-Subscriber-Id": sub, "X-Kypost-Subscriber-Hash": hash]
    }
}
```
with:
```swift
/// Relay auth credentials, sent as X-Kypost-Subscriber-Id/X-Kypost-Subscriber-Hash
/// headers on every request.
struct RelayAuth: Equatable, Sendable {
    var sub: String
    var hash: String

    init(sub: String, hash: String) {
        self.sub = sub
        self.hash = hash
    }

    init(pairing: Pairing) {
        self.init(sub: pairing.sub, hash: pairing.hash)
    }

    var headerFields: [String: String] {
        ["X-Kypost-Subscriber-Id": sub, "X-Kypost-Subscriber-Hash": hash]
    }
}
```

- [ ] **Step 3: Run the full test suite to confirm nothing broke**

Run: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS'`
Expected: SUCCESS — this is the authoritative proof that no call site
anywhere in the codebase still references the now-deleted `queryItems`; a
stray reference would fail to compile here.

- [ ] **Step 4: Commit**

```bash
git add "llama Mail for Mac/Data/Networking/HTTPClient.swift"
git commit -m "net: delete RelayAuth.queryItems, now unused after the header migration"
```

---

### Final verification (after all 7 tasks)

- [ ] Run the full test suite: `xcodebuild test -scheme "llama Mail for Mac" -destination 'platform=macOS'`
  — must succeed with zero failures.
- [ ] `grep -rln 'sub=\|hash=' --include='*.swift' "llama Mail for MacTests/"` —
  review every remaining hit by hand; the only survivors should be
  `PairingLinkParserTests`' deep-link-parsing fixtures (incoming URLs, not
  outgoing auth) and `PgpQrTests.swift`'s `fetchKey`/`keyURL` tests (the
  unrelated `t`-token path). If any hit is an outgoing-request assertion
  for one of the 5 migrated files, a test was missed.
- [ ] `grep -rn '\.queryItems\b' --include='*.swift' . | grep -v -i "DerivedData\|/build/"`
  — must return zero matches (Task 7 already deletes the property; this is
  a second, independent confirmation).
- [ ] Manual: run the app against a server running the already-shipped
  header-accepting backend and confirm device registration/pairing, mail
  fetch, folder list, mail send, attachment list/download, contact sync
  (pull/push/dedupe/photo), and PGP QR token mint all still work
  end-to-end — these endpoints now depend entirely on headers reaching the
  server correctly.

### Out of scope for this plan

- `PgpQrClient.fetchKey`, `PgpQrClient.keyURL(fromScannedPayload:)`,
  `MfaResponseClient.swift` — untouched, as documented in Global
  Constraints.
- `HTTPClient.swift`'s `get`/`getData`/`post` methods — the `headers:`
  parameter this plan uses already exists and is already correct.
- The server-side removal of legacy `?sub=&hash=` query-param support
  (Rollout Step 3 in the server's design doc) — a server-repo change gated
  on client adoption metrics, not part of this plan.
- This is the last of the four planned client/server migrations (server,
  Android, Linux, Mac) — no further sibling-repo plans are expected after
  this one, barring a new client being built later.
