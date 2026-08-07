import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/identity_trust_store.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/room_membership_manager.dart';
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

enum MessageIdentityStatus {
  local,
  seen,
  verified,
  legacyUnsigned,
  unavailable,
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
    required this.identityStatus,
  });

  final String id;
  final String text;
  final String senderLabel;
  final DateTime timestampUtc;
  final ChatMessageDirection direction;
  final ChatDeliveryStatus deliveryStatus;
  final MessageProtectionStatus protectionStatus;
  final MessageIdentityStatus identityStatus;

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
      identityStatus: identityStatus,
    );
  }
}

class ChatSessionState {
  const ChatSessionState({
    required this.profile,
    required this.secureRoom,
    required this.localIdentity,
    required this.status,
    required this.statusMessage,
    required this.messages,
    required this.peers,
    required this.pendingCount,
    this.activeTransportKind,
    this.verificationRequests = const <PeerVerificationRequest>[],
    this.trustedIdentities = const <TrustedIdentitySummary>[],
    this.roomMembers = const <RoomMemberSummary>[],
    this.hasCurrentMembership = false,
    this.isRoomOwner = false,
    this.diagnostics,
  });

  factory ChatSessionState.initial(
    LocalProfile profile,
    SecureRoomSummary secureRoom,
    DeviceIdentitySummary localIdentity,
  ) {
    return ChatSessionState(
      profile: profile,
      secureRoom: secureRoom,
      localIdentity: localIdentity,
      status: ChatConnectionStatus.initializing,
      statusMessage: 'Preparing authenticated encrypted nearby chat…',
      messages: const <ChatTimelineMessage>[],
      peers: const <NearbyPeer>[],
      pendingCount: 0,
    );
  }

  final LocalProfile profile;
  final SecureRoomSummary secureRoom;
  final DeviceIdentitySummary localIdentity;
  final ChatConnectionStatus status;
  final String statusMessage;
  final List<ChatTimelineMessage> messages;
  final List<NearbyPeer> peers;
  final int pendingCount;
  final TransportKind? activeTransportKind;
  final List<PeerVerificationRequest> verificationRequests;
  final List<TrustedIdentitySummary> trustedIdentities;
  final List<RoomMemberSummary> roomMembers;
  final bool hasCurrentMembership;
  final bool isRoomOwner;
  final TransportDiagnosticsSnapshot? diagnostics;

  List<TrustedIdentitySummary> get pendingIdentityChanges => trustedIdentities
      .where((identity) => identity.hasPendingChange)
      .toList(growable: false);

  bool get canSend =>
      hasCurrentMembership &&
      (status == ChatConnectionStatus.scanning ||
          status == ChatConnectionStatus.connected);

  bool get canOpenSettings =>
      status == ChatConnectionStatus.permissionDenied ||
      status == ChatConnectionStatus.localNetworkPermissionDenied;

  bool get canRetry =>
      status == ChatConnectionStatus.bluetoothOff ||
      status == ChatConnectionStatus.error;

  ChatSessionState copyWith({
    LocalProfile? profile,
    SecureRoomSummary? secureRoom,
    DeviceIdentitySummary? localIdentity,
    ChatConnectionStatus? status,
    String? statusMessage,
    List<ChatTimelineMessage>? messages,
    List<NearbyPeer>? peers,
    int? pendingCount,
    TransportKind? activeTransportKind,
    List<PeerVerificationRequest>? verificationRequests,
    List<TrustedIdentitySummary>? trustedIdentities,
    List<RoomMemberSummary>? roomMembers,
    bool? hasCurrentMembership,
    bool? isRoomOwner,
    TransportDiagnosticsSnapshot? diagnostics,
    bool clearActiveTransport = false,
  }) {
    return ChatSessionState(
      profile: profile ?? this.profile,
      secureRoom: secureRoom ?? this.secureRoom,
      localIdentity: localIdentity ?? this.localIdentity,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      messages: messages ?? this.messages,
      peers: peers ?? this.peers,
      pendingCount: pendingCount ?? this.pendingCount,
      activeTransportKind: clearActiveTransport
          ? null
          : activeTransportKind ?? this.activeTransportKind,
      verificationRequests: verificationRequests ?? this.verificationRequests,
      trustedIdentities: trustedIdentities ?? this.trustedIdentities,
      roomMembers: roomMembers ?? this.roomMembers,
      hasCurrentMembership:
          hasCurrentMembership ?? this.hasCurrentMembership,
      isRoomOwner: isRoomOwner ?? this.isRoomOwner,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }
}
