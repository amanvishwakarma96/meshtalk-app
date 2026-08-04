import 'package:flutter/material.dart';

typedef SendMessage = Future<void> Function(String text);

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.messages = const <String>[],
    this.onSend,
  });

  final List<String> messages;
  final SendMessage? onSend;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.onSend == null) {
      return;
    }

    await widget.onSend!(text);
    if (mounted) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MeshTalk'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(28),
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No transport connected'),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: widget.messages.isEmpty
                ? const Center(
                    child: Text('Nearby messages will appear here.'),
                  )
                : ListView.builder(
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) => ListTile(
                      key: ValueKey<String>('message-$index'),
                      title: Text(widget.messages[index]),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('message-input'),
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Message nearby peers',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey<String>('send-button'),
                    onPressed: widget.onSend == null ? null : _send,
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
