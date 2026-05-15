## 0.1.0

* Initial release.
* Headless surface: `TickkiChat` client with session lifecycle, message send/list, typing/heartbeat, attachment upload, and a private-channel realtime subscription.
* Drop-in widget: `TickkiChatWidget.show(context, ...)` opens a complete branded chat screen, fetching colors and feature flags from `/api/v1/chat/config`.
* Strings are overridable for i18n; colors are dashboard-controlled.
