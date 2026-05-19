import 'dart:async';

import '../api/api_client.dart';

/// Analytics surface for the Tickki Chat SDK.
///
/// The SDK consumer typically uses [TickkiChat.analytics] rather than
/// constructing this directly. It buffers events in memory and flushes
/// them to `POST /api/v1/chat/events` either:
///
///   - every [flushInterval] (default 5s), OR
///   - whenever the buffer reaches [bufferLimit] events, whichever
///     comes first.
///
/// Set a `visitor_id` with [setVisitorId] before tracking — without
/// one, events are dropped (we won't infer an anonymous id silently,
/// because the consumer's own user-id story is the right source of
/// truth). The drop-in widget calls this for you using the same id
/// it passes to [TickkiChat.startSession].
///
/// Three tiers of use, from least to most explicit:
///
/// 1. **Drop-in observer / scope** (zero per-widget code): see
///    `TickkiAnalyticsNavigatorObserver` and `TickkiAnalyticsScope`.
/// 2. **Per-button trackable**: see `TickkiTrackable`.
/// 3. **Manual**: call `track`, `trackScreen`, or `trackTap` from
///    anywhere with rich properties.
class TickkiAnalytics {
  TickkiAnalytics({
    required TickkiApiClient api,
    Duration flushInterval = const Duration(seconds: 5),
    int bufferLimit = 20,
    int maxBatchSize = 50,
  })  : _api = api,
        _flushInterval = flushInterval,
        _bufferLimit = bufferLimit,
        _maxBatchSize = maxBatchSize;

  final TickkiApiClient _api;
  final Duration _flushInterval;
  final int _bufferLimit;
  final int _maxBatchSize;

  String? _visitorId;
  final List<Map<String, dynamic>> _queue = [];
  Timer? _flushTimer;
  bool _flushing = false;
  bool _disposed = false;

  /// Current visitor id, or null until [setVisitorId] is called.
  String? get visitorId => _visitorId;

  /// Identify the visitor. Call once at app start (or whenever your
  /// user-id becomes known), before any track calls. Passing null
  /// pauses delivery — useful on logout.
  void setVisitorId(String? id) {
    _visitorId = id;
    if (id == null) {
      _flushTimer?.cancel();
      _flushTimer = null;
    } else {
      _ensureFlushTimer();
    }
  }

  // ---------- public tracking API --------------------------------

  /// Generic track call. Use this for custom events that don't fit
  /// the screen-view or tap shape.
  ///
  /// ```dart
  /// tickki.analytics.track(
  ///   'add_to_cart',
  ///   properties: {'product_id': 'sku-123', 'price_cents': 1999},
  /// );
  /// ```
  ///
  /// Properties are sent through to the backend's `meta` JSON column
  /// so any keys you set show up in the agent / analytics UIs.
  void track(
    String type, {
    String? title,
    String? url,
    String? elementLabel,
    String? elementType,
    String? elementKey,
    Object? value,
    Map<String, dynamic>? properties,
  }) {
    if (_disposed) return;
    if (_visitorId == null) return; // silently drop until identified
    final event = <String, dynamic>{
      'type': type,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (title != null && title.isNotEmpty) event['title'] = title;
    if (url != null && url.isNotEmpty) event['url'] = url;
    if (elementLabel != null && elementLabel.isNotEmpty) {
      event['element_label'] = elementLabel;
    }
    if (elementType != null && elementType.isNotEmpty) {
      event['element_type'] = elementType;
    }
    if (elementKey != null && elementKey.isNotEmpty) {
      event['element_key'] = elementKey;
    }
    if (value != null) event['value'] = value;
    if (properties != null && properties.isNotEmpty) {
      event['meta'] = properties;
    }
    _queue.add(event);
    if (_queue.length >= _bufferLimit) {
      // ignore: discarded_futures
      flush();
    } else {
      _ensureFlushTimer();
    }
  }

  /// Convenience for a screen / route view. The agent dashboard and
  /// Visitor Intelligence pipelines treat this as a mobile analog
  /// of `page_view`.
  ///
  /// ```dart
  /// tickki.analytics.trackScreen('CheckoutScreen');
  /// ```
  void trackScreen(String name, {Map<String, dynamic>? properties}) {
    track(
      'screen_view',
      title: name,
      url: 'tickki://$name',
      properties: properties,
    );
  }

  /// Convenience for a tap / button-press. Either pass an explicit
  /// [label] for a named tap (preferred) or use the ambient tap
  /// capture in `TickkiAnalyticsScope` for coordinate-only events.
  ///
  /// ```dart
  /// tickki.analytics.trackTap(label: 'Add to cart', key: 'add_to_cart_btn');
  /// ```
  void trackTap({
    String? label,
    String? key,
    String type = 'button',
    Map<String, dynamic>? properties,
  }) {
    track(
      'tap',
      elementLabel: label,
      elementType: type,
      elementKey: key,
      properties: properties,
    );
  }

  // ---------- flush internals ------------------------------------

  /// Force a flush of buffered events. Returns when the network
  /// round-trip is done. Safe to call manually before app teardown.
  Future<void> flush() async {
    if (_disposed) return;
    if (_flushing) return;
    final id = _visitorId;
    if (id == null) return;
    if (_queue.isEmpty) return;

    _flushing = true;
    try {
      // Drain up to maxBatchSize events. Anything left over flushes
      // on the next tick.
      final batch = _queue.take(_maxBatchSize).toList(growable: false);
      _queue.removeRange(0, batch.length);
      try {
        await _api.postJson('/chat/events', body: {
          'visitor_id': id,
          'events': batch,
        });
      } catch (_) {
        // On network failure we re-queue the batch at the head so a
        // brief outage doesn't lose events. The dedicated rate-limit
        // response from the server is also a "try again later".
        _queue.insertAll(0, batch);
      }
    } finally {
      _flushing = false;
    }
  }

  void _ensureFlushTimer() {
    if (_flushTimer != null && _flushTimer!.isActive) return;
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      // ignore: discarded_futures
      flush();
    });
  }

  /// Stop the timer and drop the queue. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    _queue.clear();
  }
}
