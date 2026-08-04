import 'package:flutter/material.dart';
import 'package:meshtalk_app/features/chat/presentation/chat_screen.dart';

class MeshTalkApp extends StatelessWidget {
  const MeshTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshTalk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}
