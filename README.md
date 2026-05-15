# Tickki Chat SDK for Flutter

Embed live customer-support chat into your Flutter app. Your users talk to your agents through the Tickki inbox — through a UI you control (or a drop-in widget you don't have to build).

- **Drop-in mode**: one method call opens a complete chat screen. Branding (colors, welcome text, logo) is fetched from the business's Tickki dashboard at runtime, so you never have to ship UI updates when the brand changes.
- **Headless mode**: the SDK exposes session, message, attachment, typing, and realtime primitives. You build whatever UI you want on top.

Both modes are in the same package — pick the import based on which one you want.

## Installation

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

## Authentication

The SDK needs a **publishable** API key (`pk_live_*`). A business owner mints one from the Tickki dashboard at `Settings → Developer` and pastes it into your build configuration. Keys are safe to embed in client code; you can restrict them to specific origins or bundle ids at creation time.

## Documentation

- **Full API reference**: <https://app.tickki.com/developers/docs>
- **Developer portal**: <https://app.tickki.com/developers>
- **Backend repo**: this SDK calls `/api/v1/chat/*`.

## License

MIT
