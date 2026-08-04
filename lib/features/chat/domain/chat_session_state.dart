import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';

enum ChatConnectionStatus {
  initializing,
  permissionDenied,
  bluetoothOff,
  unsupported,
  scanning,
  connected,
  error,
}

enum ChatMessageDirection {
  outgoing,
  incoming,
}

enum ChatDeliveryStatus {
  queued,
  sent,
  received,
}

class ChatTimelineMessage {
  const ChatTimelineMessage({
    required this.id,
    required this.text,
    required this.senderLabel,
    required this.timestampUtc,
    required this.direction,
    required this.deliveryStatus,
  });

  final String id;
  final String text;
  final String senderLabel;
  final DateTime timestampUtc;
  final ChatMessageDirection direction;
  final ChatDeliveryStatus deliveryStatus;

  ChatTimelineMessage copyWith({ChatDeliveryStatus? deliveryStatus}) {
    return ChatTimelineMessage(
      id: id,
      text: text,
      senderLabel: senderLabel,
      timestampUtc: timestampUtc,
      direction: direction,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }
}

class ChatSessionState {
  const ChatSessionState({
    required this.profile,
    required this.status,
    required this.statusMessage,
    required this.messages,
    required this.peers,
    required this.pendingCount,
  });

  factory ChatSessionState.initial(LocalProfile profile) {
    return ChatSessionState(
      profile: profile,
      status: ChatConnectionStatus.initializing,
      statusMessage: 'Preparing nearby chat…',
      messages: const <ChatTimelineMessage>[],
      peers: const <NearbyPeer>[],
      pendingCount: 0,
    );
  }

  final LocalProfile profile;
  final ChatConnectionStatus status;
  final String statusMessage;
  final List<ChatTimelineMessage> messages;
  final List<NearbyPeer> peers;
  final int pendingCount;

  bool get canSend =>
      status == ChatConnectionStatus.scanning ||
      status == ChatConnectionStatus.connected;

  bool get canOpenSettings => status == ChatConnectionStatus.permissionDenied;

  bool get canRetry =>
      status == ChatConnectionStatus.bluetoothOff ||
      status == ChatConnectionStatus.error;

  ChatSessionState copyWith({
    LocalProfile? profile,
    ChatConnectionStatus? status,
    String? statusMessage,
    List<ChatTimelineMessage>? messages,
    List<NearbyPeer>? peers,
    int? pendingCount,
  }) {
    return ChatSessionState(
      profile: profile ?? this.profile,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      messages: messages ?? this.messages,
      peers: peers ?? this.peers,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}
