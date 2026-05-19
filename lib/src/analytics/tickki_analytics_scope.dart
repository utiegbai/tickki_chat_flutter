import 'package:flutter/widgets.dart';

import 'tickki_analytics.dart';

/// Root-level wrapper that:
///
///   1. Makes [analytics] available to descendants via an
///      `InheritedWidget` (consumed by `TickkiTrackable` etc.), and
///   2. Optionally captures every pointer tap and emits a
///      coordinate-tagged `tap` event so the SDK collects an ambient
///      heatmap even without any per-button instrumentation.
///
/// Wrap once at the root:
///
/// ```dart
/// runApp(TickkiAnalyticsScope(
///   analytics: tickki.analytics,
///   child: const MyApp(),
/// ));
/// ```
///
/// Pass `captureTaps: false` to disable the ambient pointer listener
/// (the InheritedWidget surface stays available either way). Pass
/// `child:` wrapped in `TickkiIgnore` to opt subtrees out of the
/// ambient capture — useful for sensitive forms.
///
/// **Note**: ambient capture only emits coordinates and the
/// containing screen — it does not walk the Semantics tree to recover
/// a button label. For richer named events on specific widgets, use
/// [TickkiTrackable] (one wrapper per important button). Semantic
/// auto-discovery is on the roadmap for a future patch.
class TickkiAnalyticsScope extends StatefulWidget {
  const TickkiAnalyticsScope({
    super.key,
    required this.analytics,
    required this.child,
    this.captureTaps = true,
  });

  final TickkiAnalytics analytics;
  final Widget child;

  /// When true (default), every pointer-up that follows a brief
  /// pointer-down fires a `tap` event with x/y and the current
  /// route name. Disable if you want fully manual tracking.
  final bool captureTaps;

  /// Look up the nearest ancestor scope. Returns null if no scope
  /// is installed — callers should fall back gracefully.
  static TickkiAnalytics? maybeOf(BuildContext context) {
    final inh = context
        .dependOnInheritedWidgetOfExactType<_TickkiAnalyticsInheritedScope>();
    return inh?.analytics;
  }

  /// Look up the nearest ancestor scope or throw. Use inside
  /// `TickkiTrackable` builders where the scope is required.
  static TickkiAnalytics of(BuildContext context) {
    final a = maybeOf(context);
    if (a == null) {
      throw FlutterError(
        'TickkiAnalyticsScope.of(context) called with no scope in the tree. '
        'Wrap your app in a TickkiAnalyticsScope (typically inside main()).',
      );
    }
    return a;
  }

  @override
  State<TickkiAnalyticsScope> createState() => _TickkiAnalyticsScopeState();
}

class _TickkiAnalyticsScopeState extends State<TickkiAnalyticsScope> {
  // Threshold for what counts as a "tap" vs a drag — the same
  // threshold the Flutter GestureRecognizer uses (kTouchSlop is 18).
  static const double _tapSlopPx = 18.0;
  static const Duration _tapMaxDuration = Duration(milliseconds: 500);

  Offset? _downAt;
  DateTime? _downTime;

  @override
  Widget build(BuildContext context) {
    final tree = _TickkiAnalyticsInheritedScope(
      analytics: widget.analytics,
      child: widget.child,
    );
    if (!widget.captureTaps) return tree;

    // HitTestBehavior.translucent lets the pointer events pass through
    // to whatever widget below would normally handle them, while still
    // notifying us. That means we observe taps *and* the underlying
    // GestureDetectors still fire.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) {
        _downAt = null;
        _downTime = null;
      },
      child: tree,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _downAt = event.position;
    _downTime = DateTime.now();
  }

  void _onPointerUp(PointerUpEvent event) {
    final downAt = _downAt;
    final downTime = _downTime;
    _downAt = null;
    _downTime = null;
    if (downAt == null || downTime == null) return;

    final dx = (event.position.dx - downAt.dx).abs();
    final dy = (event.position.dy - downAt.dy).abs();
    if (dx > _tapSlopPx || dy > _tapSlopPx) return; // not a tap, a drag
    if (DateTime.now().difference(downTime) > _tapMaxDuration) {
      return; // too long, probably a long-press
    }

    // Is the tap inside a TickkiIgnore subtree? If yes, drop it.
    if (_TickkiIgnoreScope.isIgnored(context, event.position)) return;

    widget.analytics.track('tap', properties: {
      'x': event.position.dx.round(),
      'y': event.position.dy.round(),
      // device_pixel_ratio so analytics can normalise across devices
      'dpr': MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0,
    });
  }
}

/// Wrap a subtree that you don't want the ambient tap listener to
/// observe — typically password fields, payment forms, or anything
/// privacy-sensitive. Has no effect on explicit `track` calls or on
/// [TickkiTrackable] usage inside the subtree.
class TickkiIgnore extends StatefulWidget {
  const TickkiIgnore({super.key, required this.child});
  final Widget child;

  @override
  State<TickkiIgnore> createState() => _TickkiIgnoreState();
}

class _TickkiIgnoreState extends State<TickkiIgnore> {
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return _TickkiIgnoreScope(
      keyRef: _key,
      child: KeyedSubtree(key: _key, child: widget.child),
    );
  }
}

class _TickkiIgnoreScope extends InheritedWidget {
  const _TickkiIgnoreScope({required this.keyRef, required super.child});
  final GlobalKey keyRef;

  /// Returns true if `globalPosition` falls inside the bounding box
  /// of any ancestor TickkiIgnore subtree. Walks up via the context;
  /// fast enough for one-per-tap-frequency calls.
  static bool isIgnored(BuildContext context, Offset globalPosition) {
    bool ignored = false;
    context.visitAncestorElements((el) {
      final widget = el.widget;
      if (widget is _TickkiIgnoreScope) {
        final ctx = widget.keyRef.currentContext;
        final box = ctx?.findRenderObject();
        if (box is RenderBox && box.attached) {
          final topLeft = box.localToGlobal(Offset.zero);
          final rect = topLeft & box.size;
          if (rect.contains(globalPosition)) {
            ignored = true;
            return false;
          }
        }
      }
      return true;
    });
    return ignored;
  }

  @override
  bool updateShouldNotify(_TickkiIgnoreScope oldWidget) =>
      oldWidget.keyRef != keyRef;
}

class _TickkiAnalyticsInheritedScope extends InheritedWidget {
  const _TickkiAnalyticsInheritedScope({
    required this.analytics,
    required super.child,
  });
  final TickkiAnalytics analytics;

  @override
  bool updateShouldNotify(_TickkiAnalyticsInheritedScope oldWidget) =>
      oldWidget.analytics != analytics;
}
