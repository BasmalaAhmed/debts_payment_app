class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.paymentId,
    required this.customerId,
    required this.deviceId,
    required this.deviceSequence,
    required this.amount,
    required this.paymentStatus,
    required this.syncStatus,
    required this.createdAt,
    required this.lastError,
  });

  final String operationId;
  final String paymentId;
  final String customerId;
  final String deviceId;
  final int deviceSequence;
  final int amount;
  final String paymentStatus;
  final String syncStatus;
  final DateTime createdAt;
  final String? lastError;

  factory SyncOperation.fromRow(Map<String, Object?> row) {
    return SyncOperation(
      operationId: row['operation_id'] as String,
      paymentId: row['payment_id'] as String,
      customerId: row['customer_id'] as String,
      deviceId: row['device_id'] as String,
      deviceSequence: row['device_sequence'] as int,
      amount: row['amount'] as int,
      paymentStatus: row['payment_status'] as String,
      syncStatus: row['sync_status'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastError: row['last_error'] as String?,
    );
  }
}