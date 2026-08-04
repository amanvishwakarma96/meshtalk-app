import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshtalk_app/app_providers.dart';
import 'package:meshtalk_app/features/chat/presentation/chat_screen.dart';

class ChatPage extends ConsumerWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionValue = ref.watch(chatSessionProvider);
    return sessionValue.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('MeshTalk')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'MeshTalk could not initialize the nearby chat session.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(chatSessionProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (session) => ListenableBuilder(
        listenable: session,
        builder: (context, child) {
          return ChatScreen(
            state: session.state,
            onSend: session.send,
            onRetry: session.retry,
            onOpenSettings: session.openSettings,
          );
        },
      ),
    );
  }
}
