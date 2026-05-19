import 'package:flutter/material.dart';

import '../errors/errors.dart';
import '../models/models.dart';
import '../tickki_chat.dart';
import 'tickki_chat_strings.dart';

/// Drop-in chat screen. Opening it pushes a full-screen route that
/// fetches branding, starts (or resumes) a session, subscribes to
/// realtime updates, and renders a complete chat UI.
///
/// ```dart
/// TickkiChatWidget.show(
///   context,
///   client: tickki,
///   visitorId: 'user_8432',
/// );
/// ```
///
/// For complete UI control, use the headless API (`TickkiChat` from
/// `package:tickki_chat_flutter/tickki_chat_flutter.dart`) directly.
class TickkiChatWidget extends StatefulWidget {
  const TickkiChatWidget({
    super.key,
    required this.client,
    required this.visitorId,
    this.name,
    this.email,
    this.phone,
    this.strings = const TickkiChatStrings(),
  });

  final TickkiChat client;
  final String visitorId;
  final String? name;
  final String? email;
  final String? phone;
  final TickkiChatStrings strings;

  /// Open the chat as a full-screen modal route. Returns when the
  /// screen is dismissed.
  static Future<void> show(
    BuildContext context, {
    required TickkiChat client,
    required String visitorId,
    String? name,
    String? email,
    String? phone,
    TickkiChatStrings strings = const TickkiChatStrings(),
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TickkiChatWidget(
          client: client,
          visitorId: visitorId,
          name: name,
          email: email,
          phone: phone,
          strings: strings,
        ),
      ),
    );
  }

  @override
  State<TickkiChatWidget> createState() => _TickkiChatWidgetState();
}

class _TickkiChatWidgetState extends State<TickkiChatWidget>
    with WidgetsBindingObserver {
  ChatConfig? _config;
  ChatSession? _session;
  String? _error;
  bool _loading = true;

  // We render newest-at-bottom; the list maintains its own copy in
  // chronological order (oldest -> newest) so insertions are append.
  final List<ChatMessage> _messages = [];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // For the pre-chat form (only used when the business requires
  // identification AND no name/email was passed to the widget).
  final TextEditingController _preNameController = TextEditingController();
  final TextEditingController _preEmailController = TextEditingController();
  bool _showingPreChat = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  /// Two-stage init: fetch config → decide whether to show a pre-chat
  /// form or start the session straight away. We keep this state in
  /// the widget itself because the drop-in needs to be self-contained.
  Future<void> _bootstrap() async {
    // Reset state so the "Try again" button gets a clean slate — leaked
    // sessions or stale errors from a prior attempt would otherwise
    // leak into the next try.
    final priorSession = _session;
    setState(() {
      _loading = true;
      _error = null;
      _session = null;
      _messages.clear();
    });
    if (priorSession != null) {
      // Best-effort cleanup of the previous failed attempt.
      // ignore: discarded_futures
      priorSession.dispose();
    }
    try {
      final config = await widget.client.fetchConfig();
      if (!mounted) return;
      _config = config;

      final needsPreChat =
          config.requiresIdentificationOnStart && (widget.email ?? '').isEmpty;
      if (needsPreChat) {
        setState(() {
          _loading = false;
          _showingPreChat = true;
        });
        return;
      }
      await _startSession(
        name: widget.name,
        email: widget.email,
        phone: widget.phone,
      );
    } on TickkiChatException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _humanizeError(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.strings.errorGeneric;
        });
      }
    }
  }

  Future<void> _startSession({String? name, String? email, String? phone}) async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final session = await widget.client.startSession(
        visitorId: widget.visitorId,
        name: name,
        email: email,
        phone: phone,
      );
      if (!mounted) {
        await session.dispose();
        return;
      }
      _session = session;
      // Subscribe + heartbeat while the chat is visible.
      session.messages.listen(_onIncomingMessage);
      session.startHeartbeat();
      // Backfill the most recent page so the user sees prior context.
      final page = await session.loadHistory();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages.reversed); // oldest-first
        _loading = false;
        _showingPreChat = false;
        _starting = false;
      });
      _scrollToBottom();
    } on TickkiChatException catch (e) {
      if (!mounted) return;
      setState(() {
        // Clear `_loading` too — without this the build method
        // short-circuits on `_loading` before it ever reads `_error`,
        // leaving the spinner visible forever even though startSession
        // or loadHistory threw. Same applies to the catch-all below.
        _loading = false;
        _starting = false;
        _error = _humanizeError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _starting = false;
        _error = widget.strings.errorGeneric;
      });
    }
  }

  void _onIncomingMessage(ChatMessage m) {
    if (!mounted) return;
    // Deduplicate — sends are echoed back over the channel, so the
    // REST 201 + the broadcast both arrive for the same id. Keep
    // whichever showed up first.
    if (_messages.any((existing) => existing.id == m.id)) return;
    setState(() => _messages.add(m));
    _scrollToBottom();
  }

  Future<void> _sendCurrent() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _session == null) return;
    _inputController.clear();
    try {
      final created = await _session!.send(text);
      // Show immediately. The realtime echo will skip via the dedupe.
      _onIncomingMessage(created);
    } on TickkiChatException catch (e) {
      _showError(_humanizeError(e));
    } catch (_) {
      _showError(widget.strings.errorGeneric);
    }
  }

  String _humanizeError(TickkiChatException e) {
    if (e.isRateLimited) return widget.strings.errorRateLimited;
    return e.message;
  }

  void _showError(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------- lifecycle ----------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop the heartbeat while backgrounded — the agent's "online"
    // indicator should reflect that the user actually has the chat
    // open, not just that the app process is alive.
    final s = _session;
    if (s == null) return;
    if (state == AppLifecycleState.resumed) {
      s.startHeartbeat();
    } else {
      s.stopHeartbeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _preNameController.dispose();
    _preEmailController.dispose();
    _scrollController.dispose();
    _session?.dispose();
    super.dispose();
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final primary = _parseColor(_config?.branding.primaryColor) ??
        const Color(0xFF4F46E5);
    final accent = _parseColor(_config?.branding.accentColor) ??
        const Color(0xFF111827);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: _ChatTopBar(
          primary: primary,
          businessName: _config?.business.name,
          logoUrl: _config?.branding.logoUrl,
          agentsOnline: _config?.agentsOnline ?? 0,
          onlineLabel: widget.strings.onlineLabel,
          offlineLabel: widget.strings.offlineLabel,
          fallbackTitle: widget.strings.title,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _buildBody(primary, accent, theme),
    );
  }

  Widget _buildBody(Color primary, Color accent, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // `_error` is only ever set by the bootstrap path — mid-chat
    // failures use a snackbar, not setState. So showing the error
    // screen whenever `_error` is set is correct, even if `_session`
    // is non-null (which happens when startSession succeeded but
    // loadHistory failed afterwards).
    if (_error != null) {
      return _buildErrorState(primary);
    }
    if (_showingPreChat) {
      return _buildPreChat(primary);
    }
    return Column(
      children: [
        Expanded(child: _buildMessageList(primary, accent)),
        _buildComposer(primary),
      ],
    );
  }

  Widget _buildErrorState(Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _error ?? widget.strings.errorGeneric,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _bootstrap,
              style: FilledButton.styleFrom(backgroundColor: primary),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreChat(Color primary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.strings.preChatTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            widget.strings.preChatSubtitle,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _preNameController,
            decoration: InputDecoration(
              labelText: widget.strings.preChatNameLabel,
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _preEmailController,
            decoration: InputDecoration(
              labelText: widget.strings.preChatEmailLabel,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitPreChat(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _starting ? null : _submitPreChat,
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _starting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.strings.preChatSubmit),
          ),
        ],
      ),
    );
  }

  Future<void> _submitPreChat() async {
    final name = _preNameController.text.trim();
    final email = _preEmailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = widget.strings.preChatEmailLabel);
      return;
    }
    await _startSession(name: name, email: email);
  }

  Widget _buildMessageList(Color primary, Color accent) {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _config?.branding.welcomeMessage ?? widget.strings.emptyHistory,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: _messages[i],
        primary: primary,
        accent: accent,
      ),
    );
  }

  Widget _buildComposer(Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, -1),
            blurRadius: 6,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: widget.strings.inputPlaceholder,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  // Cheap typing indicator — kicked on every change,
                  // backend-side broadcast is itself debounced.
                  onChanged: (_) => _session?.sendTyping(),
                  onSubmitted: (_) => _sendCurrent(),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sendCurrent,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      semanticLabel: widget.strings.sendButton,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Parse `#RRGGBB` or `#AARRGGBB`. Returns null for malformed input
  /// so the caller can fall back to the SDK's defaults.
  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    var s = hex.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final value = int.tryParse(s, radix: 16);
    return value == null ? null : Color(value);
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.primary,
    required this.accent,
  });

  final ChatMessage message;
  final Color primary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final fromVisitor = message.isFromVisitor;
    final bg = fromVisitor ? primary : Colors.white;
    final fg = fromVisitor ? Colors.white : accent;
    return Align(
      alignment: fromVisitor ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(fromVisitor ? 16 : 4),
            bottomRight: Radius.circular(fromVisitor ? 4 : 16),
          ),
          boxShadow: fromVisitor
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Text(
          message.content,
          style: TextStyle(color: fg, fontSize: 14, height: 1.35),
        ),
      ),
    );
  }
}

/// Standard chat header: business logo / avatar on the left, business
/// name + online indicator in the middle, close button on the right.
/// Renders against the business's primary brand color (from
/// `GET /chat/config`'s `branding.primary_color`) with a soft bottom
/// border so it reads as a navigation bar, not a banner.
class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({
    required this.primary,
    required this.agentsOnline,
    required this.onlineLabel,
    required this.offlineLabel,
    required this.fallbackTitle,
    required this.onClose,
    this.businessName,
    this.logoUrl,
  });

  final Color primary;
  final String? businessName;
  final String? logoUrl;
  final int agentsOnline;
  final String onlineLabel;
  final String offlineLabel;
  final String fallbackTitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isOnline = agentsOnline > 0;
    final title = (businessName ?? '').isNotEmpty ? businessName! : fallbackTitle;

    return Material(
      color: primary,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
          child: Row(
            children: [
              _AvatarLogo(name: title, logoUrl: logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline
                                ? const Color(0xFF22C55E)
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? onlineLabel : offlineLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Round translucent close button — keeps the brand color
              // the dominant visual element instead of a stark white X.
              Material(
                color: Colors.white.withValues(alpha: 0.16),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo avatar with a sensible fallback. Uses NetworkImage when a
/// branding logo URL is set on the business, otherwise renders the
/// first letter of the business name on a translucent disc — so a
/// business without a logo still gets a recognisable mark instead of
/// an empty circle.
class _AvatarLogo extends StatelessWidget {
  const _AvatarLogo({required this.name, this.logoUrl});
  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();

    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          logoUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          // Same fallback as the no-URL case if the image fails to
          // load — better than a broken-image glyph in the topbar.
          errorBuilder: (_, __, ___) => _fallback(initial),
        ),
      );
    }
    return _fallback(initial);
  }

  Widget _fallback(String initial) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
