import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';

class BluetoothLowEnergyMeshRadio implements BleMeshRadio {
  BluetoothLowEnergyMeshRadio({
    required this.localName,
    CentralManager? centralManager,
    PeripheralManager? peripheralManager,
    UUID? serviceUuid,
    UUID? characteristicUuid,
  })  : _centralManager = centralManager ?? CentralManager(),
        _peripheralManager = peripheralManager ?? PeripheralManager(),
        serviceUuid = serviceUuid ??
            UUID.fromString('8d3a0001-2f5d-4c7c-9a3c-3a8f5b7d0001'),
        characteristicUuid = characteristicUuid ??
            UUID.fromString('8d3a0002-2f5d-4c7c-9a3c-3a8f5b7d0001');

  final String localName;
  final CentralManager _centralManager;
  final PeripheralManager _peripheralManager;
  final UUID serviceUuid;
  final UUID characteristicUuid;

  final StreamController<BleRadioAvailability> _availabilityChanges =
      StreamController<BleRadioAvailability>.broadcast();
  final StreamController<Uint8List> _incomingFrames =
      StreamController<Uint8List>.broadcast();
  final StreamController<List<BleRadioPeer>> _connectedPeers =
      StreamController<List<BleRadioPeer>>.broadcast();

  final Map<Peripheral, GATTCharacteristic> _outboundPeripherals =
      <Peripheral, GATTCharacteristic>{};
  final Map<Central, GATTCharacteristic> _subscribedCentrals =
      <Central, GATTCharacteristic>{};
  final Map<String, String> _peerNames = <String, String>{};
  final Set<String> _connectingPeerIds = <String>{};
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  bool _started = false;
  int _maximumFrameBytes = 20;

  @override
  BleRadioAvailability get availability {
    final states = <BluetoothLowEnergyState>[
      _centralManager.state,
      _peripheralManager.state,
    ];
    if (states.contains(BluetoothLowEnergyState.unsupported)) {
      return BleRadioAvailability.unsupported;
    }
    if (states.contains(BluetoothLowEnergyState.unauthorized)) {
      return BleRadioAvailability.unauthorized;
    }
    if (states.every((state) => state == BluetoothLowEnergyState.poweredOn)) {
      return BleRadioAvailability.ready;
    }
    return BleRadioAvailability.poweredOff;
  }

  @override
  Stream<BleRadioAvailability> get availabilityChanges =>
      _availabilityChanges.stream;

  @override
  Stream<Uint8List> get incomingFrames => _incomingFrames.stream;

  @override
  Stream<List<BleRadioPeer>> get connectedPeers => _connectedPeers.stream;

  @override
  int get maximumFrameBytes => _maximumFrameBytes;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }

    _listenToManagers();
    await _authorizeWhenNeeded();
    if (availability != BleRadioAvailability.ready) {
      await _cancelSubscriptions();
      throw StateError('Bluetooth LE is not powered on and authorized.');
    }

    final characteristic = GATTCharacteristic.mutable(
      uuid: characteristicUuid,
      properties: const <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
        GATTCharacteristicProperty.notify,
      ],
      permissions: const <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.write,
      ],
      descriptors: const <GATTDescriptor>[],
    );
    final service = GATTService(
      uuid: serviceUuid,
      isPrimary: true,
      includedServices: const <GATTService>[],
      characteristics: <GATTCharacteristic>[characteristic],
    );

    _started = true;
    try {
      await _peripheralManager.removeAllServices();
      await _peripheralManager.addService(service);
      await _peripheralManager.startAdvertising(
        Advertisement(
          name: localName,
          serviceUUIDs: <UUID>[serviceUuid],
        ),
      );
      await _centralManager.startDiscovery(
        serviceUUIDs: <UUID>[serviceUuid],
      );
      _emitAvailability();
    } catch (_) {
      _started = false;
      await _safeStopManagers();
      await _cancelSubscriptions();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_started && _subscriptions.isEmpty) {
      return;
    }

    _started = false;
    await _safeStopManagers();
    await _cancelSubscriptions();
    _outboundPeripherals.clear();
    _subscribedCentrals.clear();
    _peerNames.clear();
    _connectingPeerIds.clear();
    _maximumFrameBytes = 20;
    _publishPeers();
  }

  @override
  Future<void> sendFrame(Uint8List frame) async {
    if (!_started) {
      throw StateError('Bluetooth LE radio is not started.');
    }
    if (frame.length > _maximumFrameBytes) {
      throw ArgumentError.value(
        frame.length,
        'frame',
        'Frame exceeds the negotiated BLE payload size.',
      );
    }
    if (_outboundPeripherals.isEmpty && _subscribedCentrals.isEmpty) {
      throw StateError('No Bluetooth LE peers are connected.');
    }

    final outboundEntries =
        _outboundPeripherals.entries.toList(growable: false);
    for (final entry in outboundEntries) {
      await _centralManager.writeCharacteristic(
        entry.key,
        entry.value,
        value: Uint8List.fromList(frame),
        type: GATTCharacteristicWriteType.withoutResponse,
      );
    }

    final inboundEntries = _subscribedCentrals.entries.toList(growable: false);
    for (final entry in inboundEntries) {
      await _peripheralManager.notifyCharacteristic(
        entry.key,
        entry.value,
        value: Uint8List.fromList(frame),
      );
    }
  }

  void _listenToManagers() {
    _subscriptions
      ..add(
        _centralManager.stateChanged.listen((_) {
          _emitAvailability();
        }),
      )
      ..add(
        _peripheralManager.stateChanged.listen((_) {
          _emitAvailability();
        }),
      )
      ..add(
        _centralManager.discovered.listen((eventArgs) {
          unawaited(_connectDiscoveredPeripheral(eventArgs));
        }),
      )
      ..add(
        _centralManager.connectionStateChanged.listen((eventArgs) {
          _handlePeripheralConnectionState(eventArgs);
        }),
      )
      ..add(
        _centralManager.characteristicNotified.listen((eventArgs) {
          if (eventArgs.characteristic.uuid == characteristicUuid) {
            _incomingFrames.add(Uint8List.fromList(eventArgs.value));
          }
        }),
      )
      ..add(
        _peripheralManager.connectionStateChanged.listen((eventArgs) {
          _handleCentralConnectionState(eventArgs);
        }),
      )
      ..add(
        _peripheralManager.characteristicWriteRequested.listen((eventArgs) {
          unawaited(_handleCharacteristicWrite(eventArgs));
        }),
      )
      ..add(
        _peripheralManager.characteristicNotifyStateChanged.listen((eventArgs) {
          unawaited(_handleNotifyStateChanged(eventArgs));
        }),
      );
  }

  Future<void> _authorizeWhenNeeded() async {
    if (!Platform.isAndroid) {
      return;
    }

    if (_centralManager.state == BluetoothLowEnergyState.unauthorized) {
      await _centralManager.authorize();
    }
    if (_peripheralManager.state == BluetoothLowEnergyState.unauthorized) {
      await _peripheralManager.authorize();
    }
  }

  Future<void> _connectDiscoveredPeripheral(
    DiscoveredEventArgs eventArgs,
  ) async {
    if (!_started) {
      return;
    }

    final peripheral = eventArgs.peripheral;
    final peerId = peripheral.uuid.toString();
    if (_outboundPeripherals.containsKey(peripheral) ||
        !_connectingPeerIds.add(peerId)) {
      return;
    }

    _peerNames[peerId] = _displayName(
      eventArgs.advertisement.name,
      peerId,
    );
    try {
      await _centralManager.connect(peripheral);
      final services = await _centralManager.discoverGATT(peripheral);
      final service =
          services.where((item) => item.uuid == serviceUuid).firstOrNull;
      final characteristic = service?.characteristics
          .where((item) => item.uuid == characteristicUuid)
          .firstOrNull;
      if (characteristic == null) {
        await _centralManager.disconnect(peripheral);
        return;
      }

      await _centralManager.setCharacteristicNotifyState(
        peripheral,
        characteristic,
        state: true,
      );
      final maximumWriteLength = await _centralManager.getMaximumWriteLength(
        peripheral,
        type: GATTCharacteristicWriteType.withoutResponse,
      );
      _outboundPeripherals[peripheral] = characteristic;
      _maximumFrameBytes = _minimumFrameBytes(
        _maximumFrameBytes,
        maximumWriteLength,
      );
      _publishPeers();
    } catch (_) {
      _peerNames.remove(peerId);
    } finally {
      _connectingPeerIds.remove(peerId);
    }
  }

  void _handlePeripheralConnectionState(
    PeripheralConnectionStateChangedEventArgs eventArgs,
  ) {
    if (eventArgs.state == ConnectionState.disconnected) {
      _outboundPeripherals.remove(eventArgs.peripheral);
      _peerNames.remove(eventArgs.peripheral.uuid.toString());
      _recalculateMaximumFrameBytes();
      _publishPeers();
    }
  }

  void _handleCentralConnectionState(
    CentralConnectionStateChangedEventArgs eventArgs,
  ) {
    if (eventArgs.state == ConnectionState.disconnected) {
      _subscribedCentrals.remove(eventArgs.central);
      _peerNames.remove(eventArgs.central.uuid.toString());
      _recalculateMaximumFrameBytes();
      _publishPeers();
    }
  }

  Future<void> _handleCharacteristicWrite(
    GATTCharacteristicWriteRequestedEventArgs eventArgs,
  ) async {
    if (eventArgs.characteristic.uuid != characteristicUuid) {
      return;
    }

    await _peripheralManager.respondWriteRequest(eventArgs.request);
    if (eventArgs.request.offset == 0) {
      _incomingFrames.add(Uint8List.fromList(eventArgs.request.value));
    }
  }

  Future<void> _handleNotifyStateChanged(
    GATTCharacteristicNotifyStateChangedEventArgs eventArgs,
  ) async {
    if (eventArgs.characteristic.uuid != characteristicUuid) {
      return;
    }

    final peerId = eventArgs.central.uuid.toString();
    if (eventArgs.state) {
      _subscribedCentrals[eventArgs.central] = eventArgs.characteristic;
      _peerNames.putIfAbsent(peerId, () => _displayName(null, peerId));
      final maximumNotifyLength =
          await _peripheralManager.getMaximumNotifyLength(eventArgs.central);
      _maximumFrameBytes = _minimumFrameBytes(
        _maximumFrameBytes,
        maximumNotifyLength,
      );
    } else {
      _subscribedCentrals.remove(eventArgs.central);
      _peerNames.remove(peerId);
      _recalculateMaximumFrameBytes();
    }
    _publishPeers();
  }

  void _emitAvailability() {
    _availabilityChanges.add(availability);
  }

  void _publishPeers() {
    final peerIds = <String>{
      ..._outboundPeripherals.keys.map((peer) => peer.uuid.toString()),
      ..._subscribedCentrals.keys.map((peer) => peer.uuid.toString()),
    }.toList()
      ..sort();

    _connectedPeers.add(
      List<BleRadioPeer>.unmodifiable(
        peerIds.map(
          (peerId) => BleRadioPeer(
            id: peerId,
            displayName: _peerNames[peerId] ?? _displayName(null, peerId),
          ),
        ),
      ),
    );
  }

  void _recalculateMaximumFrameBytes() {
    // Twenty bytes is the safe ATT payload until remaining peers report a
    // fresh negotiated maximum.
    _maximumFrameBytes = 20;
  }

  int _minimumFrameBytes(int current, int candidate) {
    if (candidate <= 0) {
      return current;
    }
    if (current == 20) {
      return candidate;
    }
    return current < candidate ? current : candidate;
  }

  String _displayName(String? advertisedName, String peerId) {
    final trimmed = advertisedName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    final suffix = peerId.length <= 8 ? peerId : peerId.substring(0, 8);
    return 'MeshTalk $suffix';
  }

  Future<void> _safeStopManagers() async {
    try {
      await _centralManager.stopDiscovery();
    } catch (_) {
      // Best-effort cleanup.
    }
    try {
      await _peripheralManager.stopAdvertising();
    } catch (_) {
      // Best-effort cleanup.
    }

    final peripherals = _outboundPeripherals.keys.toList(growable: false);
    for (final peripheral in peripherals) {
      try {
        await _centralManager.disconnect(peripheral);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
    try {
      await _peripheralManager.removeAllServices();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  Future<void> _cancelSubscriptions() async {
    final subscriptions = _subscriptions.toList(growable: false);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
