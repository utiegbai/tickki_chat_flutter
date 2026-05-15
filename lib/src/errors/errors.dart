/// Exception thrown by every Tickki Chat SDK call. All HTTP and
/// realtime failures surface as one of these — branch on [code] for
/// programmatic handling and use [message] for logs / dev tools.
///
/// The [code] strings mirror the backend's stable `error` envelope
/// codes (e.g. `invalid_api_key`, `rate_limited`, `plan_gate`) — see
/// the [error reference](https://app.tickki.com/developers/docs) for
/// the full list.
class TickkiChatException implements Exception {
  TickkiChatException({
    required this.code,
    required this.message,
    this.statusCode,
    this.cause,
  });

  /// Stable machine-readable error code. Safe to switch on.
  final String code;

  /// Human-readable message suitable for logs.
  final String message;

  /// HTTP status code, when the error came from the REST API. Null
  /// for client-side failures (network errors, parse errors).
  final int? statusCode;

  /// Underlying exception, when this wraps another error. Useful for
  /// debugging but not part of the stable contract.
  final Object? cause;

  @override
  String toString() {
    final status = statusCode != null ? ' [HTTP $statusCode]' : '';
    return 'TickkiChatException($code$status): $message';
  }

  /// Convenience flag for `code == 'rate_limited'` — apps often want
  /// to apply backoff specifically for this case without a string
  /// compare at the call site.
  bool get isRateLimited => code == 'rate_limited';

  /// True when the error indicates a missing / invalid / expired
  /// credential of any kind. Apps typically retry-with-fresh-key or
  /// surface a "sign in again" UI for these.
  bool get isAuthError => const {
        'missing_api_key',
        'wrong_key_type',
        'invalid_api_key',
        'missing_session_token',
        'invalid_session',
        'origin_not_allowed',
        'business_suspended',
      }.contains(code);
}
