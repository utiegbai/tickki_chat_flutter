import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api/api_client.dart';
import 'models/models.dart';
import 'realtime/realtime_client.dart';

/// A live chat session bound to one conversation. Returned from
/// [TickkiChat.startSession]. Holds the session token internally and
/// exposes the REST + realtime primitives the SDK consumer needs.
///
/// One `ChatSession` per conversation. Call [dispose] when you're done
/// (e.g. the chat screen closes) so the realtime subscription tears
/// down and the heartbeat timer stops.
class ChatSession {
  ChatSession({
    required TickkiApiClient api,
    required StartSessionResponse details,
    Duration heartbeatInterval = const Duration(seconds: 30),
  })  : _api = api,
        _details = details,
        _heartbeatInterval = heartbeatInterval;

  final TickkiApiClient _api;
  final StartSessionResponse _details;
  final Duration _heartbeatInterval;

  TickkiRealtimeClient? _realtime;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  Completer<void>? _connected;

  // ---------- exposed identity ------------------------------------

  int get conversationId => _details.conversationId;
  int get sessionId => _details.sessionId;
  String get visitorId => _details.visitorId;
  RealtimeConfig get realtimeConfig => _details.realtime;
  StartSessionResponse get details => _details;

  /// Stream of new messages received over the realtime channel.
  /// Includes both inbound (visitor) and outbound (agent) — the
  /// backend echoes the visitor's own send back over the channel so
  /// you can use the broadcast as the source of truth for the UI.
  ///
  /// Lazily connects the websocket on first listen so consumers who
  /// only do REST never pay for a subscription they don't use.
  Stream<ChatMessage> get messages async* {
    final rt = await _ensureRealtime();
    yield* rt.messages;
  }

  // ---------- REST writes ------------------------------------------

  /// Send a text message from the visitor.
  Future<ChatMessage> send(String content) async {
    _ensureLive();
    final res = await _api.postJson(
      '/chat/sessions/$conversationId/messages',
      body: {'content': content},
      sessionToken: _details.sessionToken,
    );
    return ChatMessage.fromJson(_data(res));
  }

  /// Update the contact attached to this session.
  Future<void> identify({String? name, String? email, String? phone}) async {
    _ensureLive();
    await _api.postJson(
      '/chat/sessions/$conversationId/identify',
      body: {
        if (name != null && name.isNotEmpty) 'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
      sessionToken: _details.sessionToken,
    );
  }

  /// Fire a `visitor is typing…` indicator on the agent inbox. Cheap
  /// and fire-and-forget — the response is `{ok: true}` regardless
  /// of whether the underlying broadcast succeeded.
  Future<void> sendTyping() async {
    if (_disposed) return;
    try {
      await _api.postJson(
        '/chat/sessions/$conversationId/typing',
        sessionToken: _details.sessionToken,
      );
    } catch (_) {
      // Typing is best-effort. Surface failures via the regular send
      // path instead of leaking transient broadcast issues.
    }
  }

  /// Manual heartbeat call. Most consumers prefer [startHeartbeat]
  /// which does this on a 30s timer automatically.
  Future<void> heartbeat() async {
    if (_disposed) return;
    try {
      await _api.postJson(
        '/chat/sessions/$conversationId/heartbeat',
        sessionToken: _details.sessionToken,
      );
    } catch (_) {
      // Heartbeats are best-effort — losing one doesn't break the chat.
    }
  }

  /// Start firing [heartbeat] on a recurring timer. Call this when the
  /// chat UI becomes visible. Calling twice is a no-op.
  void startHeartbeat() {
    if (_disposed) return;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => heartbeat());
  }

  /// Stop the heartbeat timer. Call when the chat UI goes off-screen.
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Upload a file as an attachment. The backend will create a new
  /// `attachment`-type message containing the file. Returns the
  /// uploaded attachment record (including a 60-minute signed URL).
  Future<MessageAttachment> uploadAttachment(File file) async {
    _ensureLive();
    final mp = await http.MultipartFile.fromPath('file', file.path);
    final res = await _api.postMultipart(
      '/chat/sessions/$conversationId/attachments',
      files: [mp],
      sessionToken: _details.sessionToken,
    );
    final data = _data(res);
    final attachment = data['attachment'] as Map?;
    if (attachment == null) {
      throw StateError(
        'attachments endpoint returned no attachment block: $data',
      );
    }
    return MessageAttachment.fromJson(
      Map<String, dynamic>.from(attachment),
    );
  }

  // ---------- REST reads -------------------------------------------

  /// Page of message history, newest-first. Pass `cursor` from a
  /// previous response's `nextCursor` to walk older pages.
  Future<MessagePage> loadHistory({String? cursor, int limit = 30}) async {
    _ensureLive();
    final query = <String, String>{
      if (cursor != null) 'cursor': cursor,
      'limit': '$limit',
    };
    final res = await _api.getJson(
      '/chat/sessions/$conversationId/messages',
      query: query,
      sessionToken: _details.sessionToken,
    );
    final data = (res['data'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    final meta = (res['meta'] as Map?) ?? const {};
    return MessagePage(
      messages: data,
      nextCursor: meta['next_cursor'] as String?,
    );
  }

  // ---------- lifecycle --------------------------------------------

  Future<TickkiRealtimeClient> _ensureRealtime() async {
    _ensureLive();
    if (_realtime != null) {
      await _connected?.future;
      return _realtime!;
    }
    _connected = Completer<void>();
    final rt = TickkiRealtimeClient(
      realtime: _details.realtime,
      publishableKey: _api.publishableKey,
      sessionToken: _details.sessionToken,
      bundleId: _api.bundleId,
    );
    _realtime = rt;
    await rt.connect();
    _connected!.complete();
    return rt;
  }

  /// Tear down the realtime subscription and heartbeat timer. The
  /// underlying conversation stays open on the server — calling
  /// [TickkiChat.startSession] again with the same `visitor_id`
  /// resumes the same conversation.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    stopHeartbeat();
    await _realtime?.dispose();
    _realtime = null;
  }

  // ---------- internals --------------------------------------------

  void _ensureLive() {
    if (_disposed) {
      throw StateError('ChatSession has been disposed.');
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final v = envelope['data'];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }
}
