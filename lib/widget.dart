/// Tickki Chat SDK for Flutter — drop-in widget.
///
/// Importing this file gives you a complete, ready-to-show chat screen.
/// Colors, welcome copy, and feature flags are auto-fetched from the
/// Tickki backend (`GET /api/v1/chat/config`) so a business owner
/// controls branding from the Tickki dashboard — your app doesn't have
/// to know the colors.
///
/// ```dart
/// import 'package:tickki_chat_flutter/widget.dart';
///
/// // One-time at app start:
/// final tickki = TickkiChat(publishableKey: 'pk_live_…');
///
/// // Anywhere you want to open the chat:
/// TickkiChatWidget.show(context, client: tickki, visitorId: 'user_8432');
/// ```
///
/// For complete UI control instead, use the headless surface from
/// `package:tickki_chat_flutter/tickki_chat_flutter.dart` only.
library;

// Headless API stays available through the widget entry too — saves
// consumers one import in mixed-mode apps.
export 'tickki_chat_flutter.dart';
export 'src/widget/tickki_chat_widget.dart';
export 'src/widget/tickki_chat_strings.dart';
