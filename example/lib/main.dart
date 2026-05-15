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

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tickki Chat SDK Example',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final TickkiChat _client = TickkiChat(
    publishableKey: _publishableKey,
    baseUrl: _baseUrl,
  );

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

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
                onPressed: _openDropIn,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Open drop-in widget'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _openHeadless,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Open headless demo'),
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

  void _openDropIn() {
    TickkiChatWidget.show(
      context,
      client: _client,
      visitorId: _visitorId,
    );
  }

  void _openHeadless() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HeadlessChatScreen(client: _client),
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
