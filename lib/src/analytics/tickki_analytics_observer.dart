import 'package:flutter/widgets.dart';

import 'tickki_analytics.dart';

/// `NavigatorObserver` that emits a `screen_view` event whenever the
/// app pushes or replaces a route. Wire it up once on `MaterialApp.
/// navigatorObservers` and the SDK records every navigation
/// automatically — no per-screen instrumentation needed.
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [
///     TickkiAnalyticsNavigatorObserver(analytics: tickki.analytics),
///   ],
///   ...
/// )
/// ```
///
/// The screen name comes from `route.settings.name` when set; if
/// you're using `MaterialPageRoute` with a builder and no `name`, the
/// observer falls back to the route's runtime type so you still get
/// distinguishable events (just less readable). For best results,
/// give your routes names — `MaterialPageRoute(settings: RouteSettings(name: 'CheckoutScreen'), ...)`.
class TickkiAnalyticsNavigatorObserver extends NavigatorObserver {
  TickkiAnalyticsNavigatorObserver({required this.analytics});

  final TickkiAnalytics analytics;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _emit(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _emit(newRoute);
  }

  void _emit(Route<dynamic> route) {
    final name = _screenName(route);
    if (name == null) return;
    analytics.trackScreen(name);
  }

  String? _screenName(Route<dynamic> route) {
    final settingsName = route.settings.name;
    if (settingsName != null && settingsName.isNotEmpty) return settingsName;
    // Skip the modal-route Dart name spam — `MaterialPageRoute<dynamic>`
    // is rarely useful as a screen identifier. Return null and let the
    // call site drop the event.
    final type = route.runtimeType.toString();
    if (type.contains('PageRoute') || type.contains('ModalRoute')) {
      return null;
    }
    return type;
  }
}
