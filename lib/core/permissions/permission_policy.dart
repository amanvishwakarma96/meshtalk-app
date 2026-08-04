enum MeshTalkPermission {
  bluetoothScan,
  bluetoothConnect,
  foregroundLocation,
  localNetwork,
  notifications,
}

class PermissionPolicy {
  const PermissionPolicy._();

  static const Set<MeshTalkPermission> allowed = <MeshTalkPermission>{
    MeshTalkPermission.bluetoothScan,
    MeshTalkPermission.bluetoothConnect,
    MeshTalkPermission.foregroundLocation,
    MeshTalkPermission.localNetwork,
    MeshTalkPermission.notifications,
  };

  static bool isAllowed(MeshTalkPermission permission) =>
      allowed.contains(permission);
}
