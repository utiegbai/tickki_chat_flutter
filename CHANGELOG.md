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
