## 0.2.1

* **Drop-in widget topbar redesign.** Replaces the plain "Chat with
  us" AppBar with a standard chat-product header:
  - Business logo (from `branding.logo_url`) or a generated initial
    avatar on the left.
  - Business name as the title.
  - Online / offline indicator with a green-dot status pip directly
    below the name (was a separate strip before).
  - Round translucent close (×) button on the right.
  - Colour comes from `branding.primary_color` so it stays on-brand.

  All behaviour preserved — same SafeArea, same close-on-pop, same
  pre-chat / loading / error states. The `strings.title` override
  still applies when no business name is available.

## 0.2.0

* **Analytics surface added.** SDK consumers can now track screens,
  taps, and custom events that flow into the same Visitor Intelligence
  pipeline the JS widget feeds — so intent scoring, AI summaries, and
  the agent dashboard's "what is this visitor doing right now" picture
  light up for mobile traffic too.

  Three integration tiers, escalating from least to most explicit:

  1. **Auto screen tracking** — one line on `MaterialApp`:
     ```dart
     navigatorObservers: [
       TickkiAnalyticsNavigatorObserver(analytics: tickki.analytics),
     ],
     ```
     Every push / replace fires a `screen_view` event with the route
     name. Give routes names (`RouteSettings(name: 'CheckoutScreen')`)
     for readable analytics labels.

  2. **Ambient tap capture + opt-in named taps** — wrap once at the
     root:
     ```dart
     TickkiAnalyticsScope(analytics: tickki.analytics, child: MyApp())
     ```
     Captures every tap as a coordinate-tagged `tap` event without per-
     widget code. For richer events on specific buttons, wrap the child
     with `TickkiTrackable(name: 'add_to_cart_btn', label: 'Add to cart', child: ...)`.
     Wrap sensitive subtrees (password forms, payment fields) in
     `TickkiIgnore(child: ...)` to opt out of ambient capture.

  3. **Manual** — full control:
     ```dart
     tickki.analytics.setVisitorId('user_8432');
     tickki.analytics.track('add_to_cart', properties: {'sku': 'abc'});
     tickki.analytics.trackScreen('CheckoutScreen');
     tickki.analytics.trackTap(label: 'Buy now', key: 'buy_btn');
     ```

  Events are buffered in-memory and flushed every 5 seconds (or sooner
  when the buffer hits 20 events). A network failure re-queues the
  batch at the head of the buffer so a brief outage doesn't drop
  events.

* **Setup requirement**: call `tickki.analytics.setVisitorId('...')`
  before tracking. Events without a visitor id are silently dropped —
  we won't infer an anonymous id, because the consumer's own user-id
  story is the right source of truth.

* **What we deliberately do NOT track**: text input values (privacy
  poison, near-zero analytic value), scroll position (low signal on
  mobile), long-press / drag gestures (skipped in this release; let
  us know if you need them).

* No breaking changes to the existing chat surface — the analytics
  additions are net-new. Existing `TickkiChat` / `ChatSession` /
  `TickkiChatWidget` calls behave identically.

## 0.1.4

* **Realtime now actually works.** The previous releases shipped a
  `pusher_channels_flutter`-based client, but that package's native
  iOS / Android SDKs construct the WebSocket URL from a `cluster`
  name and don't expose a `host` override — so the SDK was
  connecting to Pusher Cloud (`ws-mt1.pusher.com`) instead of your
  Tickki Reverb host. Net effect: agent replies only appeared after
  the visitor closed and re-opened the chat (REST history fetch).

  Replaced with a small hand-rolled Pusher-protocol client over
  `web_socket_channel`. Connects directly to the Reverb host that
  `GET /chat/config` returns, signs the private channel through
  `POST /chat/broadcasting/auth`, and emits `MessageCreated`
  payloads on `ChatSession.messages` as they arrive. Includes
  auto-reconnect with exponential backoff capped at 30s.

* Drops the `pusher_channels_flutter` dependency, replaces it with
  `web_socket_channel ^3.0.1` (Flutter SDK-shipped dependency).

## 0.1.3

* **Fix drop-in widget stuck on loading spinner after a session-scoped
  request failed.** When `startSession` succeeded but a subsequent
  `loadHistory`/realtime call threw, the widget's catch path set
  `_error` but never cleared `_loading`, and the build method
  short-circuited on the loading state before reading `_error`. The
  net effect was an infinite spinner instead of the diagnosable error
  screen. Now the catch path resets `_loading`, the error guard no
  longer requires `_session == null`, and the bootstrap entry-point
  wipes prior state so the "Try again" button gets a clean slate.

  This downstream-bug surfaced after a backend issue where
  `resolveSession()` queried the wrong column on `chat_sdk_sessions`
  and returned 401 for SDK-issued tokens. The backend is fixed
  separately; this SDK change ensures any *future* server-side
  failure shows a real error rather than an unrecoverable spinner.

## 0.1.2

* **Fix endless loading**: cap the bundle-id auto-detect at 2 seconds.
  When `TickkiChat()` was constructed before
  `WidgetsFlutterBinding.ensureInitialized()` ran (e.g. as a top-level
  `final` outside `main()`), `PackageInfo.fromPlatform()` could hang
  indefinitely on the platform channel and the first REST call would
  block waiting for it. We now time out the lookup and fall back to a
  null bundle id — if the request then fails the key allow-list, the
  consumer gets a fast, diagnosable `origin_not_allowed` error instead
  of an infinite spinner.

## 0.1.1

* Auto-detect the host app's bundle id via `package_info_plus` and send
  it as `X-Tickki-Bundle-Id` on every request. Consumers no longer need
  to pass `bundleId:` manually when their publishable key has an
  allow-list — the SDK reads the Android `applicationId` / iOS
  `CFBundleIdentifier` at runtime. Passing `bundleId:` explicitly still
  works as an override (useful for tests or when you want to forge a
  specific identifier).
* Fixes a confusing "origin_not_allowed" failure first-time integrators
  hit when they followed the docs literally — the example app didn't
  pass `bundleId:` so the header was never sent and the allow-list
  rejected the request.

## 0.1.0

* Initial release.
* Headless surface: `TickkiChat` client with session lifecycle, message send/list, typing/heartbeat, attachment upload, and a private-channel realtime subscription.
* Drop-in widget: `TickkiChatWidget.show(context, ...)` opens a complete branded chat screen, fetching colors and feature flags from `/api/v1/chat/config`.
* Strings are overridable for i18n; colors are dashboard-controlled.
