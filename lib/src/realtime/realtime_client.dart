import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';

/// Tiny hand-rolled Pusher-protocol client over `web_socket_channel`.
///
/// Why not `pusher_channels_flutter`? That package's iOS / Android
/// native SDKs construct the WebSocket URL from a `cluster` name and
/// don't expose a `host` override — fine for Pusher Cloud, useless
/// for a self-hosted Reverb at e.g. `ws.tickki.com:443`. The Pusher
/// wire protocol is small (we only care about four message types) so
/// a custom client is cleaner than fighting the native bridges.
///
/// Lifecycle:
///   - [connect] opens the WebSocket, waits for
///     `pusher:connection_established`, calls the backend's
///     broadcasting-auth endpoint to sign the private channel, then
///     sends the `pusher:subscribe` frame.
///   - [messages] broadcasts every decoded `MessageCreated` payload.
///   - [dispose] closes the socket + cancels timers.
///
/// Reconnect is intentionally lightweight (exponential backoff capped
/// at 30s). The session token used for auth doesn't expire on its own
/// so reconnects don't need a fresh `POST /sessions`.
class TickkiRealtimeClient {
  TickkiRealtimeClient({
    required this.realtime,
    required this.publishableKey,
    required this.sessionToken,
    this.bundleId,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  final RealtimeConfig realtime;
  final String publishableKey;
  final String sessionToken;
  final String? bundleId;

  final http.Client _http;
  final bool _ownsHttp;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  String? _socketId;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  final StreamController<ChatMessage> _messages =
      StreamController<ChatMessage>.broadcast();

  /// Stream of `MessageCreated` payloads received from the server.
  /// Pipe straight to your UI state store; pings, subscription-ack,
  /// and other Pusher internal frames are filtered out before reaching
  /// the stream.
  Stream<ChatMessage> get messages => _messages.stream;

  /// Open the socket and subscribe to the private channel. Idempotent.
  Future<void> connect() async {
    if (_disposed) throw StateError('TickkiRealtimeClient has been disposed.');
    if (_channel != null) return;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    // Pusher protocol: ws[s]://host:port/app/{app_key}?protocol=7&...
    final scheme = realtime.scheme == 'https' ? 'wss' : 'ws';
    final url = Uri.parse(
      '$scheme://${realtime.host}:${realtime.port}/app/${realtime.key}'
      '?protocol=7&client=tickki_chat_flutter&version=0.1.4',
    );

    try {
      _channel = WebSocketChannel.connect(url);
      _socketSub = _channel!.stream.listen(
        _onFrame,
        onError: (e) => _onSocketDown(),
        onDone: _onSocketDown,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> frame;
    try {
      frame = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }

    final eventName = (frame['event'] ?? '').toString();
    final channelName = (frame['channel'] ?? '').toString();

    // Pusher wraps the per-event payload as a JSON-encoded string;
    // some Reverb / Laravel broadcaster combos double-encode (the
    // event class json_encodes itself, then the framing layer wraps
    // that in another encode). Two passes handle both wire formats.
    final dataField = frame['data'];
    Map<String, dynamic> data = const {};
    dynamic decoded = dataField;
    for (var pass = 0; pass < 2; pass++) {
      if (decoded is String && decoded.isNotEmpty) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {
          break;
        }
      } else {
        break;
      }
    }
    if (decoded is Map<String, dynamic>) {
      data = decoded;
    } else if (decoded is Map) {
      data = Map<String, dynamic>.from(decoded);
    }

    switch (eventName) {
      case 'pusher:connection_established':
        _socketId = (data['socket_id'] ?? '').toString();
        _reconnectAttempt = 0;
        _startPingTimer();
        _subscribePrivate();
        return;
      case 'pusher:error':
      case 'pusher:pong':
      case 'pusher:ping':
        return;
      case 'pusher_internal:subscription_succeeded':
        return;
      case 'pusher_internal:subscription_error':
        // Surface a synthetic error onto the stream so the consumer
        // sees that realtime is broken instead of silently waiting.
        // Channel auth typically fails here when the publishable key
        // / session token combo doesn't match.
        _messages.addError(StateError(
          'Realtime subscription failed for $channelName: $data',
        ));
        return;
    }

    // Only emit broadcasts on our channel + the event the backend
    // told us to bind. Anything else (cross-channel noise from a
    // shared connection, future event types we don't know yet) is
    // ignored.
    if (eventName.isEmpty) return;
    if (channelName != realtime.channel) return;
    if (eventName != realtime.event) return;

    try {
      _messages.add(ChatMessage.fromJson(data));
    } catch (_) {
      // Bad payload shape — drop silently; the REST history fetch
      // will recover the message on the next reload.
    }
  }

  /// POST to the backend's broadcasting-auth endpoint to obtain the
  /// HMAC-signed payload that the Pusher protocol requires before it
  /// admits a private-channel subscription.
  Future<void> _subscribePrivate() async {
    final sockId = _socketId;
    if (sockId == null) return;

    String? authSignature;
    try {
      final res = await _http.post(
        Uri.parse(realtime.authEndpoint),
        headers: {
          'Authorization': 'Bearer $publishableKey',
          'X-Tickki-Session': sessionToken,
          if (bundleId != null && bundleId!.isNotEmpty)
            'X-Tickki-Bundle-Id': bundleId!,
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'socket_id': sockId,
          'channel_name': realtime.channel,
        },
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map && body['auth'] is String) {
          authSignature = body['auth'] as String;
        }
      } else {
        _messages.addError(StateError(
          'broadcasting/auth failed: HTTP ${res.statusCode} — ${res.body}',
        ));
        return;
      }
    } catch (e) {
      _messages.addError(StateError('broadcasting/auth threw: $e'));
      return;
    }

    if (authSignature == null) return;
    _send({
      'event': 'pusher:subscribe',
      'data': {
        'auth': authSignature,
        'channel': realtime.channel,
      },
    });
  }

  void _send(Map<String, dynamic> frame) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(frame));
    } catch (_) {
      // The socket is in a bad state — let _onSocketDown handle it.
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    // Reverb closes idle sockets at 120s by default; pinging at 30s
    // keeps the line alive without flooding the wire.
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'event': 'pusher:ping', 'data': <String, dynamic>{}});
    });
  }

  void _onSocketDown() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _socketId = null;
    if (_disposed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_disposed) return;
    _reconnectAttempt++;
    // 1, 2, 4, 8, 16, 30, 30, ... seconds.
    final delaySeconds = (1 << (_reconnectAttempt - 1)).clamp(1, 30);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_disposed) return;
      _channel = null;
      _openSocket();
    });
  }

  /// Close the socket, cancel timers, and complete the message stream.
  /// Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    await _messages.close();
    if (_ownsHttp) _http.close();
  }
}
