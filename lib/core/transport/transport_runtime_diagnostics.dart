class TransportRuntimeError {
  const TransportRuntimeError({
    required this.transportId,
    required this.message,
  });

  final String transportId;
  final String message;
}

abstract interface class TransportRuntimeDiagnostics {
  Stream<TransportRuntimeError> get runtimeErrors;
}
