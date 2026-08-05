import Flutter
import UIKit

public final class MeshTalkMultipeerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "meshtalk.multipeer/methods"
  private static let eventChannelName = "meshtalk.multipeer/events"

  private let controller = MeshTalkMultipeerController()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MeshTalkMultipeerPlugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "start":
      guard
        let arguments = call.arguments as? [String: Any],
        let deviceId = arguments["deviceId"] as? String,
        let displayName = arguments["displayName"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "start requires deviceId and displayName.",
            details: nil
          )
        )
        return
      }
      controller.start(
        deviceId: deviceId,
        displayName: displayName,
        completion: result
      )
    case "stop":
      controller.stop(completion: result)
    case "approvePeer":
      guard let endpointId = endpointId(from: call.arguments) else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "approvePeer requires endpointId.",
            details: nil
          )
        )
        return
      }
      controller.approvePeer(endpointId, completion: result)
    case "rejectPeer":
      guard let endpointId = endpointId(from: call.arguments) else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "rejectPeer requires endpointId.",
            details: nil
          )
        )
        return
      }
      controller.rejectPeer(endpointId, completion: result)
    case "sendBytes":
      guard
        let arguments = call.arguments as? [String: Any],
        let endpointId = arguments["endpointId"] as? String,
        let typedData = arguments["bytes"] as? FlutterStandardTypedData
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "sendBytes requires endpointId and bytes.",
            details: nil
          )
        )
        return
      }
      controller.sendBytes(
        endpointId: endpointId,
        data: typedData.data,
        completion: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    controller.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    controller.eventSink = nil
    return nil
  }

  private func endpointId(from arguments: Any?) -> String? {
    guard let map = arguments as? [String: Any] else {
      return nil
    }
    return map["endpointId"] as? String
  }
}
