/// Tickki Chat SDK for Flutter — headless surface.
///
/// Import this file to get the API client + realtime primitives without
/// pulling in any widgets. Use this when you're building your own chat
/// UI on top of Tickki.
///
/// ```dart
/// import 'package:tickki_chat_flutter/tickki_chat_flutter.dart';
///
/// final tickki = TickkiChat(publishableKey: 'pk_live_…');
/// final session = await tickki.startSession(visitorId: 'user_8432');
/// session.messages.listen((m) => print('${m.direction}: ${m.content}'));
/// await session.send('Hello!');
/// ```
///
/// For the pre-built chat screen instead, import
/// `package:tickki_chat_flutter/widget.dart`.
library;

// Public re-exports. Implementation lives under `src/` so we can
// refactor internals without breaking consumers.
export 'src/tickki_chat.dart';
export 'src/models/models.dart';
export 'src/errors/errors.dart';
