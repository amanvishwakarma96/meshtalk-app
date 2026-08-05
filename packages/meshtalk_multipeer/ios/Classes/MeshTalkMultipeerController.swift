import CryptoKit
import Flutter
import Foundation
import MultipeerConnectivity

final class MeshTalkMultipeerController: NSObject {
  private static let serviceType = "meshtalk-chat"
  private static let verificationTimeout: TimeInterval = 45
  private static let connectionTimeout: TimeInterval = 35

  var eventSink: FlutterEventSink?

  private var localDeviceId = ""
  private var localDisplayName = "MeshTalk"
  private var localNonce = ""
  private var localPeerId: MCPeerID?
  private var session: MCSession?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var started = false

  private var pendingPeers: [String: PendingPeer] = [:]
  private var devicePeers: [String: MCPeerID] = [:]
  private var peerDeviceIds: [MCPeerID: String] = [:]
  private var peerDisplayNames: [String: String] = [:]
  private var verifiedDeviceIds: Set<String> = []
  private var connectedDeviceIds: Set<String> = []

  func start(
    deviceId: String,
    displayName: String,
    completion: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      guard self.isValidDeviceId(deviceId) else {
        completion(
          FlutterError(
            code: "invalid_device_id",
            message: "The local MeshTalk device ID is invalid.",
            details: nil
          )
        )
        return
      }

      if self.started && self.localDeviceId == deviceId {
        completion(nil)
        return
      }

      self.stopInternal(emitStopped: false)
      self.localDeviceId = deviceId
      self.localDisplayName = self.sanitizeDisplayName(displayName)
      self.localNonce = UUID().uuidString
        .replacingOccurrences(of: "-", with: "")
        .lowercased()

      let peerId = MCPeerID(displayName: self.localDisplayName)
      let session = MCSession(
        peer: peerId,
        securityIdentity: nil,
        encryptionPreference: .required
      )
      session.delegate = self

      let discoveryInfo = [
        "deviceId": self.localDeviceId,
        "displayName": self.localDisplayName,
        "nonce": self.localNonce,
      ]
      let advertiser = MCNearbyServiceAdvertiser(
        peer: peerId,
        discoveryInfo: discoveryInfo,
        serviceType: Self.serviceType
      )
      advertiser.delegate = self
      let browser = MCNearbyServiceBrowser(
        peer: peerId,
        serviceType: Self.serviceType
      )
      browser.delegate = self

      self.localPeerId = peerId
      self.session = session
      self.advertiser = advertiser
      self.browser = browser
      self.started = true

      advertiser.startAdvertisingPeer()
      browser.startBrowsingForPeers()
      self.emit(["type": "started"])
      completion(nil)
    }
  }

  func stop(completion: @escaping FlutterResult) {
    DispatchQueue.main.async {
      self.stopInternal(emitStopped: true)
      completion(nil)
    }
  }

  func approvePeer(
    _ endpointId: String,
    completion: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      guard
        self.started,
        let pending = self.pendingPeers[endpointId],
        let session = self.session
      else {
        completion(
          FlutterError(
            code: "stale_verification",
            message: "The peer verification request is no longer available.",
            details: endpointId
          )
        )
        return
      }

      self.verifiedDeviceIds.insert(endpointId)
      pending.timeoutTimer?.invalidate()
      self.emitVerificationRemoved(endpointId)

      switch pending.direction {
      case .outgoing:
        guard
          let browser = self.browser,
          let context = pending.invitationContext
        else {
          self.cleanupPending(endpointId, emitRemoval: false)
          completion(
            FlutterError(
              code: "invitation_unavailable",
              message: "The iOS peer invitation is no longer available.",
              details: endpointId
            )
          )
          return
        }
        pending.invitationSent = true
        browser.invitePeer(
          pending.peerId,
          to: session,
          withContext: context,
          timeout: Self.connectionTimeout
        )
      case .incoming:
        guard let invitationHandler = pending.invitationHandler else {
          self.cleanupPending(endpointId, emitRemoval: false)
          completion(
            FlutterError(
              code: "invitation_unavailable",
              message: "The incoming iOS invitation has expired.",
              details: endpointId
            )
          )
          return
        }
        pending.invitationHandler = nil
        invitationHandler(true, session)
      }

      pending.timeoutTimer = self.scheduleTimeout(
        endpointId: endpointId,
        interval: Self.connectionTimeout,
        message: "The verified iOS peer did not finish connecting in time."
      )
      completion(nil)
    }
  }

  func rejectPeer(
    _ endpointId: String,
    completion: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      guard let pending = self.pendingPeers[endpointId] else {
        completion(nil)
        return
      }

      pending.invitationHandler?(false, nil)
      pending.invitationHandler = nil
      if pending.invitationSent {
        self.session?.cancelConnectPeer(pending.peerId)
      }
      self.verifiedDeviceIds.remove(endpointId)
      self.cleanupPending(endpointId, emitRemoval: true)
      completion(nil)
    }
  }

  func sendBytes(
    endpointId: String,
    data: Data,
    completion: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      guard
        self.started,
        self.connectedDeviceIds.contains(endpointId),
        self.verifiedDeviceIds.contains(endpointId),
        let peerId = self.devicePeers[endpointId],
        let session = self.session,
        session.connectedPeers.contains(peerId)
      else {
        completion(
          FlutterError(
            code: "peer_not_connected",
            message: "The verified iOS peer is not connected.",
            details: endpointId
          )
        )
        return
      }

      do {
        try session.send(data, toPeers: [peerId], with: .reliable)
        completion(nil)
      } catch {
        completion(
          FlutterError(
            code: "send_failed",
            message: "The iOS peer payload could not be sent.",
            details: error.localizedDescription
          )
        )
      }
    }
  }

  private func stopInternal(emitStopped: Bool) {
    guard started || session != nil else {
      return
    }

    started = false
    advertiser?.stopAdvertisingPeer()
    browser?.stopBrowsingForPeers()
    session?.disconnect()

    for pending in pendingPeers.values {
      pending.timeoutTimer?.invalidate()
      pending.invitationHandler?(false, nil)
      pending.invitationHandler = nil
    }

    pendingPeers.removeAll()
    devicePeers.removeAll()
    peerDeviceIds.removeAll()
    peerDisplayNames.removeAll()
    verifiedDeviceIds.removeAll()
    connectedDeviceIds.removeAll()
    advertiser = nil
    browser = nil
    session = nil
    localPeerId = nil

    if emitStopped {
      emit(["type": "stopped"])
    }
  }

  private func handleFoundPeer(
    _ peerId: MCPeerID,
    discoveryInfo: [String: String]?
  ) {
    guard
      started,
      let discoveryInfo,
      let endpointId = discoveryInfo["deviceId"],
      let remoteNonce = discoveryInfo["nonce"],
      !remoteNonce.isEmpty,
      isValidDeviceId(endpointId),
      endpointId != localDeviceId
    else {
      return
    }

    let displayName = sanitizeDisplayName(
      discoveryInfo["displayName"] ?? peerId.displayName
    )
    devicePeers[endpointId] = peerId
    peerDeviceIds[peerId] = endpointId
    peerDisplayNames[endpointId] = displayName

    guard
      localDeviceId < endpointId,
      !connectedDeviceIds.contains(endpointId),
      pendingPeers[endpointId] == nil
    else {
      return
    }

    let token = verificationToken(
      remoteDeviceId: endpointId,
      remoteNonce: remoteNonce
    )
    guard
      let context = invitationContext(
        receiverId: endpointId,
        receiverNonce: remoteNonce
      )
    else {
      return
    }

    let pending = PendingPeer(
      endpointId: endpointId,
      peerId: peerId,
      displayName: displayName,
      authenticationToken: token,
      direction: .outgoing
    )
    pending.invitationContext = context
    pending.timeoutTimer = scheduleTimeout(
      endpointId: endpointId,
      interval: Self.verificationTimeout,
      message: "The iOS peer verification request expired."
    )
    pendingPeers[endpointId] = pending
    emitVerificationRequest(pending)
  }

  private func handleLostPeer(_ peerId: MCPeerID) {
    guard let endpointId = peerDeviceIds[peerId] else {
      return
    }
    guard !connectedDeviceIds.contains(endpointId) else {
      return
    }

    if let pending = pendingPeers[endpointId], pending.direction == .outgoing {
      verifiedDeviceIds.remove(endpointId)
      cleanupPending(endpointId, emitRemoval: true)
    }
    devicePeers.removeValue(forKey: endpointId)
    peerDeviceIds.removeValue(forKey: peerId)
    peerDisplayNames.removeValue(forKey: endpointId)
  }

  private func handleInvitation(
    from peerId: MCPeerID,
    context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    guard
      started,
      let context,
      let payload = try? JSONDecoder().decode(
        InvitationPayload.self,
        from: context
      ),
      payload.version == 1,
      payload.receiverId == localDeviceId,
      payload.receiverNonce == localNonce,
      payload.senderId < localDeviceId,
      isValidDeviceId(payload.senderId),
      !payload.senderNonce.isEmpty,
      !connectedDeviceIds.contains(payload.senderId),
      pendingPeers[payload.senderId] == nil
    else {
      invitationHandler(false, nil)
      return
    }

    let displayName = sanitizeDisplayName(payload.senderName)
    let token = verificationToken(
      remoteDeviceId: payload.senderId,
      remoteNonce: payload.senderNonce
    )
    let pending = PendingPeer(
      endpointId: payload.senderId,
      peerId: peerId,
      displayName: displayName,
      authenticationToken: token,
      direction: .incoming
    )
    pending.invitationHandler = invitationHandler
    pending.timeoutTimer = scheduleTimeout(
      endpointId: payload.senderId,
      interval: Self.verificationTimeout,
      message: "The incoming iOS peer verification request expired."
    )

    devicePeers[payload.senderId] = peerId
    peerDeviceIds[peerId] = payload.senderId
    peerDisplayNames[payload.senderId] = displayName
    pendingPeers[payload.senderId] = pending
    emitVerificationRequest(pending)
  }

  private func handlePeerState(
    _ peerId: MCPeerID,
    state: MCSessionState
  ) {
    guard let endpointId = peerDeviceIds[peerId] else {
      return
    }

    switch state {
    case .connected:
      guard verifiedDeviceIds.contains(endpointId) else {
        session?.cancelConnectPeer(peerId)
        emitError(
          "An unverified iOS peer attempted to complete a connection.",
          endpointId: endpointId
        )
        return
      }
      connectedDeviceIds.insert(endpointId)
      cleanupPending(endpointId, emitRemoval: false)
      emit([
        "type": "peerConnected",
        "endpointId": endpointId,
        "peerId": endpointId,
        "displayName": peerDisplayNames[endpointId] ?? peerId.displayName,
      ])
    case .notConnected:
      let wasConnected = connectedDeviceIds.remove(endpointId) != nil
      verifiedDeviceIds.remove(endpointId)
      cleanupPending(endpointId, emitRemoval: true)
      devicePeers.removeValue(forKey: endpointId)
      peerDeviceIds.removeValue(forKey: peerId)
      peerDisplayNames.removeValue(forKey: endpointId)
      if wasConnected {
        emit([
          "type": "peerDisconnected",
          "endpointId": endpointId,
          "peerId": endpointId,
        ])
        restartBrowsingAfterDisconnect()
      }
    case .connecting:
      break
    @unknown default:
      break
    }
  }

  private func handleReceivedData(_ data: Data, from peerId: MCPeerID) {
    guard
      let endpointId = peerDeviceIds[peerId],
      connectedDeviceIds.contains(endpointId),
      verifiedDeviceIds.contains(endpointId)
    else {
      return
    }

    emit([
      "type": "bytesReceived",
      "endpointId": endpointId,
      "peerId": endpointId,
      "bytes": FlutterStandardTypedData(bytes: data),
    ])
  }

  private func invitationContext(
    receiverId: String,
    receiverNonce: String
  ) -> Data? {
    let payload = InvitationPayload(
      version: 1,
      senderId: localDeviceId,
      senderName: localDisplayName,
      senderNonce: localNonce,
      receiverId: receiverId,
      receiverNonce: receiverNonce
    )
    return try? JSONEncoder().encode(payload)
  }

  private func verificationToken(
    remoteDeviceId: String,
    remoteNonce: String
  ) -> String {
    let localPart = "\(localDeviceId):\(localNonce)"
    let remotePart = "\(remoteDeviceId):\(remoteNonce)"
    let material = [localPart, remotePart].sorted().joined(separator: "|")
    let digest = SHA256.hash(data: Data(material.utf8))
    let prefix = digest.prefix(4)
    let number = prefix.reduce(0) { partial, byte in
      ((partial << 8) | Int(byte)) & 0x7fffffff
    } % 1_000_000
    return String(format: "%06d", number)
  }

  private func scheduleTimeout(
    endpointId: String,
    interval: TimeInterval,
    message: String
  ) -> Timer {
    return Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
      [weak self] _ in
      guard let self, let pending = self.pendingPeers[endpointId] else {
        return
      }
      pending.invitationHandler?(false, nil)
      pending.invitationHandler = nil
      if pending.invitationSent {
        self.session?.cancelConnectPeer(pending.peerId)
      }
      self.verifiedDeviceIds.remove(endpointId)
      self.cleanupPending(endpointId, emitRemoval: true)
      self.emitError(message, endpointId: endpointId)
    }
  }

  private func cleanupPending(_ endpointId: String, emitRemoval: Bool) {
    guard let pending = pendingPeers.removeValue(forKey: endpointId) else {
      return
    }
    pending.timeoutTimer?.invalidate()
    pending.timeoutTimer = nil
    if emitRemoval {
      emitVerificationRemoved(endpointId)
    }
  }

  private func restartBrowsingAfterDisconnect() {
    guard started, let browser else {
      return
    }
    browser.stopBrowsingForPeers()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self, self.started else {
        return
      }
      self.browser?.startBrowsingForPeers()
    }
  }

  private func emitVerificationRequest(_ pending: PendingPeer) {
    emit([
      "type": "verificationRequested",
      "endpointId": pending.endpointId,
      "peerId": pending.endpointId,
      "displayName": pending.displayName,
      "authenticationToken": pending.authenticationToken,
      "isIncomingConnection": pending.direction == .incoming,
    ])
  }

  private func emitVerificationRemoved(_ endpointId: String) {
    emit([
      "type": "verificationRemoved",
      "endpointId": endpointId,
    ])
  }

  private func emitError(_ message: String, endpointId: String? = nil) {
    var event: [String: Any] = [
      "type": "error",
      "message": message,
    ]
    if let endpointId {
      event["endpointId"] = endpointId
    }
    emit(event)
  }

  private func emit(_ event: [String: Any]) {
    if Thread.isMainThread {
      eventSink?(event)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.eventSink?(event)
      }
    }
  }

  private func isValidDeviceId(_ value: String) -> Bool {
    guard (8...64).contains(value.count) else {
      return false
    }
    let allowed = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-")
    )
    return value.unicodeScalars.allSatisfy { allowed.contains($0) }
  }

  private func sanitizeDisplayName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: " _-")
    )
    let filtered = String(
      value.unicodeScalars.filter { allowed.contains($0) }
    )
    let normalized = filtered
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
    let fallback = normalized.isEmpty ? "MeshTalk" : normalized
    return String(fallback.prefix(20))
  }
}

extension MeshTalkMultipeerController: MCNearbyServiceBrowserDelegate {
  func browser(
    _ browser: MCNearbyServiceBrowser,
    foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    DispatchQueue.main.async {
      self.handleFoundPeer(peerID, discoveryInfo: info)
    }
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    DispatchQueue.main.async {
      self.handleLostPeer(peerID)
    }
  }

  func browser(
    _ browser: MCNearbyServiceBrowser,
    didNotStartBrowsingForPeers error: Error
  ) {
    DispatchQueue.main.async {
      self.emitError(
        "iOS Multipeer browsing could not start: \(error.localizedDescription)"
      )
    }
  }
}

extension MeshTalkMultipeerController: MCNearbyServiceAdvertiserDelegate {
  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    DispatchQueue.main.async {
      self.handleInvitation(
        from: peerID,
        context: context,
        invitationHandler: invitationHandler
      )
    }
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didNotStartAdvertisingPeer error: Error
  ) {
    DispatchQueue.main.async {
      self.emitError(
        "iOS Multipeer advertising could not start: \(error.localizedDescription)"
      )
    }
  }
}

extension MeshTalkMultipeerController: MCSessionDelegate {
  func session(
    _ session: MCSession,
    peer peerID: MCPeerID,
    didChange state: MCSessionState
  ) {
    DispatchQueue.main.async {
      self.handlePeerState(peerID, state: state)
    }
  }

  func session(
    _ session: MCSession,
    didReceive data: Data,
    fromPeer peerID: MCPeerID
  ) {
    DispatchQueue.main.async {
      self.handleReceivedData(data, from: peerID)
    }
  }

  func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}

  func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {}

  func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {}
}

private final class PendingPeer {
  enum Direction {
    case outgoing
    case incoming
  }

  init(
    endpointId: String,
    peerId: MCPeerID,
    displayName: String,
    authenticationToken: String,
    direction: Direction
  ) {
    self.endpointId = endpointId
    self.peerId = peerId
    self.displayName = displayName
    self.authenticationToken = authenticationToken
    self.direction = direction
  }

  let endpointId: String
  let peerId: MCPeerID
  let displayName: String
  let authenticationToken: String
  let direction: Direction
  var invitationHandler: ((Bool, MCSession?) -> Void)?
  var invitationContext: Data?
  var invitationSent = false
  var timeoutTimer: Timer?
}

private struct InvitationPayload: Codable {
  let version: Int
  let senderId: String
  let senderName: String
  let senderNonce: String
  let receiverId: String
  let receiverNonce: String
}
