import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tickki_chat_flutter/widget.dart';

/// Tickki Chat SDK example. Two screens:
///   1. Drop-in widget — one tap opens the full chat UI.
///   2. Headless demo — REST + realtime primitives, your own bare-bones UI.
///
/// Replace the publishable key below with one minted from your
/// Tickki dashboard at /settings/developer/{slug}. The visitor id
/// is whatever stable string you'd persist for the current user.
void main() {
  runApp(const ExampleApp());
}

const _publishableKey = 'pk_live_PASTE_YOUR_KEY_HERE';
const _visitorId = 'demo-visitor-001';
const _baseUrl = 'https://app.tickki.com';

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});
  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  // Single TickkiChat for the whole app. The drop-in widget, the
  // headless demo screen, and the analytics surface all share it.
  late final TickkiChat _client = TickkiChat(
    publishableKey: _publishableKey,
    baseUrl: _baseUrl,
  )..analytics.setVisitorId(_visitorId);

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TickkiAnalyticsScope wraps the app once. Its job:
    //   1. Make `tickki.analytics` reachable from TickkiTrackable
    //      widgets anywhere below.
    //   2. Capture ambient taps (coordinates + screen) so we get a
    //      heatmap-style stream without per-button instrumentation.
    //      Disable with `captureTaps: false` for fully manual tracking.
    return TickkiAnalyticsScope(
      analytics: _client.analytics,
      child: MaterialApp(
        title: 'Tickki Chat SDK Example',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF4F46E5),
        ),
        // The navigator observer fires a `screen_view` for every push /
        // replace. Give your routes names for readable screen labels.
        navigatorObservers: [
          TickkiAnalyticsNavigatorObserver(analytics: _client.analytics),
        ],
        home: _Home(client: _client),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({required this.client});
  final TickkiChat client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tickki Chat SDK')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => _openDropIn(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Open drop-in widget'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _openHeadless(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Open headless demo'),
              ),
              const SizedBox(height: 12),
              // Tier-3 analytics: explicit named tap on a button you
              // care about. Wrap the child with TickkiTrackable, give
              // it a stable name + visible label, and the SDK fires a
              // rich `tap` event when it's tapped. The button below
              // does no real work — it's purely to demo the event.
              TickkiTrackable(
                name: 'demo_track_event_btn',
                label: 'Fire a custom event',
                properties: const {'demo': true},
                child: OutlinedButton(
                  onPressed: () {
                    // Tier-3 manual track call — for events that don't
                    // fit screen-view or tap shapes.
                    client.analytics.track(
                      'add_to_cart',
                      properties: const {
                        'product_id': 'sku-123',
                        'price_cents': 1999,
                      },
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Fired tap + add_to_cart events. They\'ll appear in the Tickki analytics within ~5s.',
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Fire add_to_cart event'),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Edit lib/main.dart and paste your publishable key from\n'
                'Tickki → Settings → Developer before running.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDropIn(BuildContext context) {
    TickkiChatWidget.show(
      context,
      client: client,
      visitorId: _visitorId,
    );
  }

  void _openHeadless(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        // Naming the route makes the screen_view event readable in
        // the analytics dashboard ("HeadlessChatScreen" vs. an
        // auto-derived runtime type).
        settings: const RouteSettings(name: 'HeadlessChatScreen'),
        builder: (_) => _HeadlessChatScreen(client: client),
      ),
    );
  }
}

/// Bare-bones screen showing how to drive the SDK from your own UI:
/// `startSession` → listen to `messages` → call `send`. The widget
/// styling is intentionally minimal — the point is the API shape.
class _HeadlessChatScreen extends StatefulWidget {
  const _HeadlessChatScreen({required this.client});
  final TickkiChat client;
  @override
  State<_HeadlessChatScreen> createState() => _HeadlessChatScreenState();
}

class _HeadlessChatScreenState extends State<_HeadlessChatScreen> {
  ChatSession? _session;
  final List<ChatMessage> _log = [];
  final TextEditingController _input = TextEditingController();
  String? _error;
  StreamSubscription<ChatMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final s = await widget.client.startSession(visitorId: _visitorId);
      _sub = s.messages.listen((m) {
        if (_log.any((existing) => existing.id == m.id)) return;
        setState(() => _log.add(m));
      });
      s.startHeartbeat();
      final page = await s.loadHistory();
      if (!mounted) return;
      setState(() {
        _session = s;
        _log.addAll(page.messages.reversed);
      });
    } on TickkiChatException catch (e) {
      setState(() => _error = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session?.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Headless example')),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _log.length,
              itemBuilder: (_, i) {
                final m = _log[i];
                final mine = m.isFromVisitor;
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: mine
                          ? const Color(0xFF4F46E5)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      m.content,
                      style: TextStyle(
                        color: mine ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Send a message…',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _session == null ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _session == null) return;
    _input.clear();
    try {
      final m = await _session!.send(text);
      if (_log.any((existing) => existing.id == m.id)) return;
      setState(() => _log.add(m));
    } on TickkiChatException catch (e) {
      setState(() => _error = '${e.code}: ${e.message}');
    }
  }
}
