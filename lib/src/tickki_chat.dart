import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'api/api_client.dart';
import 'chat_session.dart';
import 'models/models.dart';

export 'chat_session.dart' show ChatSession;

/// Entry point for the Tickki Chat SDK.
///
/// Create one of these at app start and reuse it for every chat
/// session — it owns the HTTP client and the publishable key. The
/// constructor is `const`-cheap; nothing happens on the network until
/// you call one of the methods.
///
/// ```dart
/// final tickki = TickkiChat(publishableKey: 'pk_live_…');
/// final config = await tickki.fetchConfig();
/// final session = await tickki.startSession(visitorId: 'user_8432');
/// ```
class TickkiChat {
  TickkiChat({
    required this.publishableKey,
    this.baseUrl = 'https://app.tickki.com',
    this.bundleId,
    http.Client? httpClient,
  }) : _api = TickkiApiClient(
          publishableKey: publishableKey,
          baseUrl: baseUrl,
          bundleId: bundleId,
          // When no explicit bundleId was passed, kick off a lookup
          // via package_info_plus. The ApiClient awaits this Future
          // on the first request and caches the result; the consumer
          // never sees the async detail.
          bundleIdFuture: bundleId == null ? _autoDetectBundleId() : null,
          httpClient: httpClient,
        );

  /// `pk_live_*` key minted from the Tickki dashboard. Safe to embed.
  final String publishableKey;

  /// Base URL of the Tickki backend. Defaults to the hosted product;
  /// override for self-hosted deployments or local development.
  final String baseUrl;

  /// Optional override for the bundle id sent as `X-Tickki-Bundle-Id`.
  /// When null (the default), the SDK auto-detects it via
  /// `package_info_plus` so the consumer doesn't have to wire this
  /// up themselves — `flutter pub add tickki_chat_flutter` and your
  /// app's bundle id is already on the wire.
  final String? bundleId;

  final TickkiApiClient _api;

  /// One-shot lookup of the host app's package identifier. Wrapped
  /// in a try/catch because on unsupported platforms (or rare init
  /// failures) `PackageInfo.fromPlatform()` throws — and a bundle-id
  /// lookup failure must never break the actual chat call.
  static Future<String?> _autoDetectBundleId() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final id = info.packageName;
      return (id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Direct access to the underlying API client. Use this when you
  /// need to call something the SDK doesn't surface a typed method for
  /// (rare — open an issue if you have to). Most consumers will never
  /// touch this.
  TickkiApiClient get api => _api;

  /// One-shot fetch of branding, feature flags, and agent presence.
  /// Call once at app start, before opening the chat — the drop-in
  /// widget uses this to paint the right colors and gate features
  /// like file uploads.
  Future<ChatConfig> fetchConfig() async {
    final res = await _api.getJson('/chat/config');
    final data = res['data'];
    return ChatConfig.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }

  /// Start (or resume) a chat session for the given visitor.
  ///
  /// [visitorId] is your stable identifier for the user — typically
  /// your own user id when signed in, or a generated uuid stashed in
  /// secure storage when anonymous. Reusing the same id later resumes
  /// the same conversation, so previously-sent messages stay visible.
  ///
  /// [name], [email], [phone] populate the Tickki Contact record so
  /// agents see who they're talking to. Required on first start when
  /// the business has "require contact on start" enabled (check
  /// [ChatConfig.requiresIdentificationOnStart] before calling).
  Future<ChatSession> startSession({
    required String visitorId,
    String? name,
    String? email,
    String? phone,
  }) async {
    final res = await _api.postJson('/chat/sessions', body: {
      'visitor_id': visitorId,
      if (name != null && name.isNotEmpty) 'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
    final data = res['data'];
    final details = StartSessionResponse.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
    return ChatSession(api: _api, details: details);
  }

  /// Release the HTTP client. Call from your `dispose`/`tearDown`
  /// path when the app is shutting down (rarely needed in production).
  void close() => _api.close();
}
