import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/errors.dart';

/// Thin HTTP client that knows three things the Tickki backend cares
/// about:
///
/// 1. The publishable API key, sent as `Authorization: Bearer pk_live_…`.
/// 2. The optional per-session token, sent as `X-Tickki-Session`.
/// 3. The bundle id (mobile) or origin (web), for the key allow-list.
///
/// Everything else is generic JSON over HTTP. We deliberately keep
/// this small so consumers can swap in their own transport (e.g.
/// dio with retry interceptors) by passing a custom [httpClient].
class TickkiApiClient {
  TickkiApiClient({
    required this.publishableKey,
    required this.baseUrl,
    String? bundleId,
    Future<String?>? bundleIdFuture,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        // The initializer list needs the local `bundleId` param for
        // the conditional below, so we can't use `this.bundleId` here.
        // ignore: prefer_initializing_formals
        bundleId = bundleId,
        _bundleIdFuture = bundleId != null ? null : bundleIdFuture;

  /// `pk_live_*` key minted from the Tickki dashboard.
  final String publishableKey;

  /// Absolute base URL up to (but not including) `/api/v1`. The
  /// production value is `https://app.tickki.com` — pass your own host
  /// for self-hosted deployments or local testing.
  final String baseUrl;

  /// Sent as `X-Tickki-Bundle-Id` so the backend can match against the
  /// key's allow-list. When the consumer passes an explicit value to
  /// [TickkiChat], we use it directly. Otherwise [TickkiChat] kicks off
  /// a `package_info_plus` lookup and feeds the result here on first
  /// request, transparently to the consumer.
  String? bundleId;

  /// Pending async resolution of the bundle id. Set when no explicit
  /// value was passed; cleared after the first request awaits it.
  Future<String?>? _bundleIdFuture;

  final http.Client _http;
  final bool _ownsHttp;

  // ---------- public helpers ---------------------------------------

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    String? sessionToken,
  }) async {
    await _ensureBundleIdResolved();
    final uri = _buildUri(path, query);
    final res = await _http.get(uri, headers: _headers(sessionToken: sessionToken));
    return _decode(res);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? sessionToken,
  }) async {
    await _ensureBundleIdResolved();
    final uri = _buildUri(path, null);
    final res = await _http.post(
      uri,
      headers: _headers(sessionToken: sessionToken, json: true),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  /// `multipart/form-data` POST for attachment uploads. The caller
  /// passes ready-made `http.MultipartFile`s so the SDK doesn't care
  /// whether the file came from disk (`fromPath`) or memory
  /// (`fromBytes`).
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<http.MultipartFile> files,
    Map<String, String>? fields,
    String? sessionToken,
  }) async {
    await _ensureBundleIdResolved();
    final req = http.MultipartRequest('POST', _buildUri(path, null));
    req.headers.addAll(_headers(sessionToken: sessionToken));
    if (fields != null) req.fields.addAll(fields);
    req.files.addAll(files);
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  /// Awaits the pending bundle-id lookup on the first request, then
  /// drops the future so subsequent requests are a no-op. Swallowing
  /// errors is intentional — a failed package_info lookup must not
  /// poison the actual REST call.
  Future<void> _ensureBundleIdResolved() async {
    if (bundleId != null) return;
    final f = _bundleIdFuture;
    if (f == null) return;
    _bundleIdFuture = null;
    try {
      bundleId = await f;
    } catch (_) {
      bundleId = null;
    }
  }

  void close() {
    if (_ownsHttp) _http.close();
  }

  // ---------- private ----------------------------------------------

  Uri _buildUri(String path, Map<String, String>? query) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final full = '$cleanBase/api/v1$cleanPath';
    final uri = Uri.parse(full);
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      ...query,
    });
  }

  Map<String, String> _headers({String? sessionToken, bool json = false}) {
    final id = bundleId;
    return {
      'Authorization': 'Bearer $publishableKey',
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (sessionToken != null) 'X-Tickki-Session': sessionToken,
      if (id != null && id.isNotEmpty) 'X-Tickki-Bundle-Id': id,
    };
  }

  /// Unwraps the `{ data: … }` envelope the backend uses, or raises
  /// a [TickkiChatException] with the stable `error` code on failure.
  Map<String, dynamic> _decode(http.Response res) {
    final raw = res.body;
    Map<String, dynamic>? body;
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        // fall through — we'll raise a parse error below if needed
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body == null) {
        throw TickkiChatException(
          code: 'parse_error',
          message: 'Server returned a non-JSON success response.',
          statusCode: res.statusCode,
        );
      }
      // Most endpoints wrap the payload in `{ data: ... }`, but a
      // few return bare `{ ok: true }` shapes (heartbeat, typing).
      // Return the whole body and let the typed call site unwrap.
      return body;
    }

    // Error path. Match the backend's documented envelope:
    //   { error: "<code>", message: "<human readable>" }
    final code = body?['error']?.toString() ?? 'http_${res.statusCode}';
    final msg = body?['message']?.toString() ??
        'Request failed with HTTP ${res.statusCode}.';
    throw TickkiChatException(
      code: code,
      message: msg,
      statusCode: res.statusCode,
    );
  }
}
