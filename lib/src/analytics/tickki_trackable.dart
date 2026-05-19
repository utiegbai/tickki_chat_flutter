import 'package:flutter/widgets.dart';

import 'tickki_analytics.dart';
import 'tickki_analytics_scope.dart';

/// One-line wrapper that emits a named `tap` event when the child is
/// tapped. Use this on buttons / clickable rows you care about
/// analytically — leave the rest to ambient capture from
/// [TickkiAnalyticsScope].
///
/// ```dart
/// TickkiTrackable(
///   name: 'add_to_cart_btn',
///   label: 'Add to cart',
///   child: ElevatedButton(onPressed: addToCart, child: const Text('Add to cart')),
/// )
/// ```
///
/// Requires a [TickkiAnalyticsScope] ancestor. If [analytics] is
/// passed explicitly, the scope isn't required.
class TickkiTrackable extends StatelessWidget {
  const TickkiTrackable({
    super.key,
    required this.child,
    this.name,
    this.label,
    this.elementType = 'button',
    this.properties,
    this.analytics,
  });

  /// The widget you want to instrument. Typically a button or
  /// list-tile-style row.
  final Widget child;

  /// Stable identifier for the element — kept across re-renders.
  /// Surfaces in analytics queries as `element_key`.
  final String? name;

  /// Human-readable label, e.g. the button's visible text. Surfaces
  /// in the agent UI and in analytics as `element_label`.
  final String? label;

  /// Loose category for grouping. Default `'button'`; use `'link'`,
  /// `'icon'`, `'row'`, etc. as fits your UI vocabulary.
  final String elementType;

  /// Optional bag of additional fields persisted into the event's
  /// `meta` column. Use for product ids, list positions, etc.
  final Map<String, dynamic>? properties;

  /// Override the analytics instance. When null, the widget reads
  /// from the nearest `TickkiAnalyticsScope`. Pass this only for
  /// tests or when the scope isn't installed.
  final TickkiAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    // Listener with translucent hit-testing so the wrapped child still
    // receives the tap. We don't use GestureDetector because that
    // would compete with the child's own gesture handlers (most
    // notably the button's InkWell).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (_) {
        final a = analytics ?? TickkiAnalyticsScope.maybeOf(context);
        if (a == null) return;
        a.trackTap(
          label: label,
          key: name,
          type: elementType,
          properties: properties,
        );
      },
      child: child,
    );
  }
}
