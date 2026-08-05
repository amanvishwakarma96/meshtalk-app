import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshtalk_app/app_providers.dart';
import 'package:meshtalk_app/features/chat/presentation/chat_screen.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    ref.read(chatSessionProvider).whenData((session) {
      unawaited(session.onAppResumed());
    });
  }

  @override
  Widget build(BuildContext context) {
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
            onApprovePeer: session.approvePeer,
            onRejectPeer: session.rejectPeer,
            onUpdateDisplayName: (displayName) async {
              await ref
                  .read(profileStoreProvider)
                  .updateDisplayName(displayName);
              await session.close();
              ref.invalidate(localProfileProvider);
              ref.invalidate(chatSessionProvider);
            },
          );
        },
      ),
    );
  }
}
