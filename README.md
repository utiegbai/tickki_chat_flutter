# Tickki Chat SDK for Flutter

[![pub.dev](https://img.shields.io/pub/v/tickki_chat_flutter.svg)](https://pub.dev/packages/tickki_chat_flutter)
[![pub points](https://img.shields.io/pub/points/tickki_chat_flutter)](https://pub.dev/packages/tickki_chat_flutter/score)

Embed live customer-support chat into your Flutter app. Your users talk to your agents through the Tickki inbox — through a UI you control (or a drop-in widget you don't have to build).

- **Drop-in mode**: one method call opens a complete chat screen. Branding (colors, welcome text, logo) is fetched from the business's Tickki dashboard at runtime, so you never have to ship UI updates when the brand changes.
- **Headless mode**: the SDK exposes session, message, attachment, typing, and realtime primitives. You build whatever UI you want on top.

Both modes are in the same package — pick the import based on which one you want.

## Installation

```sh
flutter pub add tickki_chat_flutter
```

…or add it to `pubspec.yaml` manually:

```yaml
dependencies:
  tickki_chat_flutter: ^0.1.0
```

## Quick start — drop-in widget

```dart
import 'package:flutter/material.dart';
import 'package:tickki_chat_flutter/widget.dart';

final tickki = TickkiChat(publishableKey: 'pk_live_…');

// Anywhere you want to open the chat:
TickkiChatWidget.show(
  context,
  client: tickki,
  visitorId: 'user_8432', // a stable id you persist for the user
);
```

That's it. The widget pulls colors, welcome message, and feature flags from `GET /api/v1/chat/config` and renders accordingly.

You can also pass `strings:` to override the English labels for i18n:

```dart
TickkiChatWidget.show(
  context,
  client: tickki,
  visitorId: 'user_8432',
  strings: TickkiChatStrings(
    sendButton: 'Envoyer',
    inputPlaceholder: 'Tapez un message…',
  ),
);
```

## Quick start — headless

```dart
import 'package:tickki_chat_flutter/tickki_chat_flutter.dart';

final tickki = TickkiChat(publishableKey: 'pk_live_…');

final session = await tickki.startSession(
  visitorId: 'user_8432',
  name: 'Jane Doe',
  email: 'jane@example.com',
);

// Listen for new messages from agents (and your own echo back).
session.messages.listen((m) {
  print('${m.direction}: ${m.content}');
});

// Send a message.
await session.send('Hi, my order hasn\'t arrived.');

// Get history (e.g. when re-opening the chat).
final history = await session.loadHistory();

// When you're done (e.g. the user closes the chat).
await session.dispose();
```

## Analytics — tracking screens, taps, and custom events

The SDK also has an analytics surface that feeds the same Visitor Intelligence pipeline the JS widget uses. Three integration tiers, from least to most explicit:

### 1. Zero per-widget code — auto screen tracking

```dart
final tickki = TickkiChat(publishableKey: 'pk_live_…')
  ..analytics.setVisitorId('user_8432');

MaterialApp(
  navigatorObservers: [
    TickkiAnalyticsNavigatorObserver(analytics: tickki.analytics),
  ],
  ...
)
```

Every push / replace fires a `screen_view` event with the route name. For readable labels, give your routes names: `MaterialPageRoute(settings: RouteSettings(name: 'CheckoutScreen'), builder: ...)`.

### 2. One wrapper for the whole app — ambient tap capture + named taps

```dart
runApp(TickkiAnalyticsScope(
  analytics: tickki.analytics,
  child: const MyApp(),
));
```

`TickkiAnalyticsScope` captures every tap and records it as a coordinate-tagged `tap` event — a free heatmap, no per-widget code.

For richer events on specific buttons, wrap the child with `TickkiTrackable`:

```dart
TickkiTrackable(
  name: 'add_to_cart_btn',          // stable id, used as element_key
  label: 'Add to cart',              // human-readable, used as element_label
  child: ElevatedButton(onPressed: ..., child: const Text('Add to cart')),
)
```

For sensitive subtrees (password fields, payment forms), wrap with `TickkiIgnore`:

```dart
TickkiIgnore(child: PasswordField(...))
```

### 3. Manual — full control

```dart
tickki.analytics.track('add_to_cart', properties: {'sku': 'abc-123', 'price_cents': 1999});
tickki.analytics.trackScreen('CheckoutScreen');
tickki.analytics.trackTap(label: 'Buy now', key: 'buy_btn');
```

Events buffer in memory and flush every 5 seconds (or sooner if the buffer hits 20 events). Network failures re-queue the batch so brief outages don't drop events.

## Authentication

The SDK needs a **publishable** API key (`pk_live_*`). A business owner mints one from the Tickki dashboard at `Settings → Developer` and pastes it into your build configuration. Keys are safe to embed in client code; you can restrict them to specific origins or bundle ids at creation time.

## Documentation

- **Full API reference**: <https://app.tickki.com/developers/docs>
- **Developer portal**: <https://app.tickki.com/developers>
- **Backend repo**: this SDK calls `/api/v1/chat/*`.

## License

MIT
