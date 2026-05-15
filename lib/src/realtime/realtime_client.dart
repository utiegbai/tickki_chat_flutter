import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../models/models.dart';

/// Wraps `pusher_channels_flutter` so the rest of the SDK can speak
/// "subscribe to a channel and tell me when a [ChatMessage] arrives"
/// without caring about the Pusher protocol details.
///
/// The Tickki backend speaks the Pusher protocol via Laravel Reverb,
/// so this class works against any Pusher / Reverb endpoint as long
/// as the `auth_endpoint` returns the right HMAC signature shape
/// (which our `/api/v1/chat/broadcasting/auth` does — see
/// [ChatSessionController::broadcastingAuth] on the backend).
///
/// One instance is owned per [ChatSession]. On `dispose` we unsubscribe
/// but leave the underlying Pusher connection up — subsequent sessions
/// in the same app share the same socket.
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

  PusherChannelsFlutter? _pusher;
  StreamController<ChatMessage>? _messages;
  bool _disposed = false;

  /// Broadcasts inbound + outbound messages received over the channel.
  /// You typically pipe this straight to your UI's state store.
  Stream<ChatMessage> get messages =>
      (_messages ??= StreamController<ChatMessage>.broadcast()).stream;

  /// Initialise the Pusher singleton, connect, subscribe. Idempotent —
  /// safe to call more than once for the same session (subsequent
  /// calls no-op).
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('Realtime client has been disposed.');
    }
    if (_pusher != null) return;

    final pusher = PusherChannelsFlutter.getInstance();
    _pusher = pusher;

    await pusher.init(
      apiKey: realtime.key,
      // Reverb doesn't use Pusher's region-based clusters; the
      // `pusher_channels_flutter` API requires *some* value here so
      // we pass a literal "mt1" (matches the default that Reverb's
      // js client uses).
      cluster: 'mt1',
      useTLS: realtime.scheme == 'https',
      onAuthorizer: _authorizer,
      onEvent: _onEvent,
    );
    await pusher.connect();
    await pusher.subscribe(channelName: realtime.channel);
  }

  /// Pusher private-channel auth callback. Forwards `socket_id` +
  /// `channel_name` to the backend's `/api/v1/chat/broadcasting/auth`
  /// with the publishable key and session token, then returns the
  /// signed payload the Pusher SDK expects.
  ///
  /// The return shape is what `pusher_channels_flutter` documents:
  /// `{ "auth": "<key>:<signature>" }`. Throwing here surfaces the
  /// failure to the consumer's `onSubscriptionError` if they set one.
  Future<dynamic> _authorizer(
    String channelName,
    String socketId,
    dynamic options,
  ) async {
    final res = await _http.post(
      Uri.parse(realtime.authEndpoint),
      headers: {
        'Authorization': 'Bearer $publishableKey',
        'X-Tickki-Session': sessionToken,
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        if (bundleId != null) 'X-Tickki-Bundle-Id': bundleId!,
      },
      body: {
        'socket_id': socketId,
        'channel_name': channelName,
      },
    );
    if (res.statusCode != 200) {
      throw StateError(
        'broadcasting/auth failed: HTTP ${res.statusCode} — ${res.body}',
      );
    }
    return jsonDecode(res.body);
  }

  void _onEvent(PusherEvent event) {
    if (event.channelName != realtime.channel) return;
    if (event.eventName != realtime.event) return;

    final raw = event.data;
    Map<String, dynamic>? payload;
    if (raw is Map) {
      payload = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Pusher occasionally hands us already-decoded payloads on
        // some platforms; the conditional above handles those. If
        // neither path worked, silently drop — better than crashing
        // the listener.
      }
    }
    if (payload == null) return;
    _messages?.add(ChatMessage.fromJson(payload));
  }

  /// Unsubscribe + close the message stream. Leaves the Pusher
  /// singleton alive so other sessions in the same process reuse the
  /// socket — calling [PusherChannelsFlutter.disconnect] would
  /// disconnect them too.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _pusher?.unsubscribe(channelName: realtime.channel);
    } catch (_) {
      // best-effort
    }
    await _messages?.close();
    _messages = null;
    if (_ownsHttp) _http.close();
  }
}
