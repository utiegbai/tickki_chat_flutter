/// Plain Dart DTOs for the Tickki Chat REST surface. Mirrors the
/// shapes documented in the OpenAPI spec under
/// `components.schemas.*` — see
/// <https://app.tickki.com/developers/docs/spec> for the source of
/// truth.
///
/// Every model exposes a `fromJson(Map<String, dynamic>)` factory.
/// Fields are typed as nullable when the backend documents them as
/// nullable; required fields throw if missing rather than silently
/// defaulting (would hide a contract drift).

library;

/// Branding + feature flags + presence returned by `GET /chat/config`.
class ChatConfig {
  ChatConfig({
    required this.business,
    required this.branding,
    required this.features,
    required this.limits,
    required this.agentsOnline,
    required this.requiresIdentificationOnStart,
  });

  final BusinessInfo business;
  final BrandingInfo branding;
  final FeaturesInfo features;
  final LimitsInfo limits;

  /// Number of agents whose presence is `online` right now. UI typically
  /// shows "Online" when > 0 and "We'll get back to you" otherwise.
  final int agentsOnline;

  /// When true, `POST /chat/sessions` rejects anonymous starts — the
  /// SDK should display a pre-chat form before calling startSession.
  final bool requiresIdentificationOnStart;

  factory ChatConfig.fromJson(Map<String, dynamic> j) {
    final presence = (j['presence'] as Map?) ?? const {};
    final identification = (j['identification'] as Map?) ?? const {};
    return ChatConfig(
      business: BusinessInfo.fromJson(_map(j['business'])),
      branding: BrandingInfo.fromJson(_map(j['branding'])),
      features: FeaturesInfo.fromJson(_map(j['features'])),
      limits: LimitsInfo.fromJson(_map(j['limits'])),
      agentsOnline: (presence['agents_online'] as num?)?.toInt() ?? 0,
      requiresIdentificationOnStart:
          identification['required_on_start'] == true,
    );
  }
}

class BusinessInfo {
  BusinessInfo({required this.id, required this.name, required this.slug});
  final int id;
  final String name;
  final String slug;
  factory BusinessInfo.fromJson(Map<String, dynamic> j) => BusinessInfo(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '').toString(),
        slug: (j['slug'] ?? '').toString(),
      );
}

class BrandingInfo {
  BrandingInfo({
    required this.primaryColor,
    required this.accentColor,
    required this.welcomeMessage,
    this.logoUrl,
  });
  final String primaryColor;
  final String accentColor;
  final String welcomeMessage;
  final String? logoUrl;
  factory BrandingInfo.fromJson(Map<String, dynamic> j) => BrandingInfo(
        primaryColor: (j['primary_color'] ?? '#4F46E5').toString(),
        accentColor: (j['accent_color'] ?? '#111827').toString(),
        welcomeMessage:
            (j['welcome_message'] ?? 'Hi! How can we help?').toString(),
        logoUrl: j['logo_url'] as String?,
      );
}

class FeaturesInfo {
  FeaturesInfo({required this.fileUploads, required this.voiceNotes});
  final bool fileUploads;
  final bool voiceNotes;
  factory FeaturesInfo.fromJson(Map<String, dynamic> j) => FeaturesInfo(
        fileUploads: j['file_uploads'] == true,
        voiceNotes: j['voice_notes'] == true,
      );
}

class LimitsInfo {
  LimitsInfo({required this.maxUploadKb, required this.messageMaxLength});
  final int maxUploadKb;
  final int messageMaxLength;
  factory LimitsInfo.fromJson(Map<String, dynamic> j) => LimitsInfo(
        maxUploadKb: (j['max_upload_kb'] as num?)?.toInt() ?? 5120,
        messageMaxLength: (j['message_max_length'] as num?)?.toInt() ?? 8000,
      );
}

/// Server-issued realtime config returned alongside a newly-started
/// session. Hand straight to the Pusher / Reverb client.
class RealtimeConfig {
  RealtimeConfig({
    required this.key,
    required this.host,
    required this.port,
    required this.scheme,
    required this.channel,
    required this.authEndpoint,
    required this.event,
  });

  /// Pusher / Reverb **app** key — NOT the same as the publishable
  /// API key on the consumer side.
  final String key;
  final String host;
  final int port;
  final String scheme; // 'http' | 'https'
  final String channel; // e.g. 'private-chat.session.904'
  final String authEndpoint;
  final String event; // event name to bind on the channel

  factory RealtimeConfig.fromJson(Map<String, dynamic> j) => RealtimeConfig(
        key: (j['key'] ?? '').toString(),
        host: (j['host'] ?? '').toString(),
        port: (j['port'] as num?)?.toInt() ?? 443,
        scheme: (j['scheme'] ?? 'https').toString(),
        channel: (j['channel'] ?? '').toString(),
        authEndpoint: (j['auth_endpoint'] ?? '').toString(),
        event: (j['event'] ?? 'MessageCreated').toString(),
      );
}

/// What `POST /chat/sessions` returns. The [sessionToken] field is
/// shown to the caller exactly once — persist it in memory for the
/// lifetime of the chat.
class StartSessionResponse {
  StartSessionResponse({
    required this.sessionId,
    required this.sessionToken,
    required this.conversationId,
    required this.visitorId,
    required this.contactName,
    this.contactEmail,
    required this.realtime,
  });

  final int sessionId;
  final String sessionToken;
  final int conversationId;
  final String visitorId;
  final String? contactName;
  final String? contactEmail;
  final RealtimeConfig realtime;

  factory StartSessionResponse.fromJson(Map<String, dynamic> j) {
    final contact = (j['contact'] as Map?) ?? const {};
    return StartSessionResponse(
      sessionId: (j['session_id'] as num).toInt(),
      sessionToken: (j['session_token'] ?? '').toString(),
      conversationId: (j['conversation_id'] as num).toInt(),
      visitorId: (j['visitor_id'] ?? '').toString(),
      contactName: contact['name'] as String?,
      contactEmail: contact['email'] as String?,
      realtime: RealtimeConfig.fromJson(_map(j['realtime'])),
    );
  }
}

/// One message in a conversation. `direction == 'inbound'` was sent
/// by the visitor (your user); `'outbound'` was sent by an agent.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.direction,
    required this.type,
    required this.content,
    required this.createdAt,
    this.attachments = const [],
  });

  final int id;
  final MessageDirection direction;

  /// `'text'` or `'attachment'`. For `'attachment'`, the realtime
  /// broadcast payload also includes [attachments] entries with
  /// signed URLs — REST list responses do not. Use the broadcast
  /// payload for inline rendering, or refetch on history reload.
  final String type;
  final String content;
  final DateTime createdAt;
  final List<MessageAttachment> attachments;

  bool get isFromAgent => direction == MessageDirection.outbound;
  bool get isFromVisitor => direction == MessageDirection.inbound;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] as num).toInt(),
        direction:
            ((j['direction'] ?? 'inbound').toString() == 'outbound')
                ? MessageDirection.outbound
                : MessageDirection.inbound,
        type: (j['type'] ?? 'text').toString(),
        content: (j['content'] ?? '').toString(),
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '') ??
                DateTime.now().toUtc(),
        attachments: (j['attachments'] as List?)
                ?.whereType<Map>()
                .map((m) => MessageAttachment.fromJson(
                    Map<String, dynamic>.from(m)))
                .toList(growable: false) ??
            const [],
      );
}

enum MessageDirection { inbound, outbound }

class MessageAttachment {
  MessageAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.signedUrl,
  });
  final int id;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? signedUrl;
  factory MessageAttachment.fromJson(Map<String, dynamic> j) =>
      MessageAttachment(
        id: (j['id'] as num).toInt(),
        fileName: (j['file_name'] ?? '').toString(),
        mimeType: (j['mime_type'] ?? 'application/octet-stream').toString(),
        fileSize: (j['file_size'] as num?)?.toInt() ?? 0,
        signedUrl: j['signed_url'] as String?,
      );
}

/// A paginated slice of messages — what `GET /sessions/{id}/messages`
/// returns. [nextCursor] is null when there is no older page.
class MessagePage {
  MessagePage({required this.messages, this.nextCursor});
  final List<ChatMessage> messages;
  final String? nextCursor;
}

Map<String, dynamic> _map(dynamic v) => v is Map
    ? Map<String, dynamic>.from(v)
    : <String, dynamic>{};
