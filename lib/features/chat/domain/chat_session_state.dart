import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/features/chat/domain/transport_diagnostics.dart';

enum ChatConnectionStatus {
  initializing,
  permissionDenied,
  localNetworkPermissionDenied,
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
    required this.protectionStatus,
  });

  final String id;
  final String text;
  final String senderLabel;
  final DateTime timestampUtc;
  final ChatMessageDirection direction;
  final ChatDeliveryStatus deliveryStatus;
  final MessageProtectionStatus protectionStatus;

  ChatTimelineMessage copyWith({ChatDeliveryStatus? deliveryStatus}) {
    return ChatTimelineMessage(
      id: id,
      text: text,
      senderLabel: senderLabel,
      timestampUtc: timestampUtc,
      direction: direction,
      deliveryStatus: direction == ChatMessageDirection.incoming
          ? this.deliveryStatus
          : deliveryStatus ?? this.deliveryStatus,
      protectionStatus: protectionStatus,
    );
  }
}

class ChatSessionState {
  const ChatSessionState({
    required this.profile,
    required this.secureRoom,
    required this.status,
    required this.statusMessage,
    required this.messages,
    required this.peers,
    required this.pendingCount,
    this.activeTransportKind,
    this.verificationRequests = const <PeerVerificationRequest>[],
    this.diagnostics,
  });

  factory ChatSessionState.initial(
    LocalProfile profile,
    SecureRoomSummary secureRoom,
  ) {
    return ChatSessionState(
      profile: profile,
      secureRoom: secureRoom,
      status: ChatConnectionStatus.initializing,
      statusMessage: 'Preparing encrypted nearby chat…',
      messages: const <ChatTimelineMessage>[],
      peers: const <NearbyPeer>[],
      pendingCount: 0,
    );
  }

  final LocalProfile profile;
  final SecureRoomSummary secureRoom;
  final ChatConnectionStatus status;
  final String statusMessage;
  final List<ChatTimelineMessage> messages;
  final List<NearbyPeer> peers;
  final int pendingCount;
  final TransportKind? activeTransportKind;
  final List<PeerVerificationRequest> verificationRequests;
  final TransportDiagnosticsSnapshot? diagnostics;

  bool get canSend =>
      status == ChatConnectionStatus.scanning ||
      status == ChatConnectionStatus.connected;

  bool get canOpenSettings =>
      status == ChatConnectionStatus.permissionDenied ||
      status == ChatConnectionStatus.localNetworkPermissionDenied;

  bool get canRetry =>
      status == ChatConnectionStatus.bluetoothOff ||
      status == ChatConnectionStatus.error;

  ChatSessionState copyWith({
    LocalProfile? profile,
    SecureRoomSummary? secureRoom,
    ChatConnectionStatus? status,
    String? statusMessage,
    List<ChatTimelineMessage>? messages,
    List<NearbyPeer>? peers,
    int? pendingCount,
    TransportKind? activeTransportKind,
    List<PeerVerificationRequest>? verificationRequests,
    TransportDiagnosticsSnapshot? diagnostics,
    bool clearActiveTransport = false,
  }) {
    return ChatSessionState(
      profile: profile ?? this.profile,
      secureRoom: secureRoom ?? this.secureRoom,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      messages: messages ?? this.messages,
      peers: peers ?? this.peers,
      pendingCount: pendingCount ?? this.pendingCount,
      activeTransportKind: clearActiveTransport
          ? null
          : activeTransportKind ?? this.activeTransportKind,
      verificationRequests: verificationRequests ?? this.verificationRequests,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }
}
