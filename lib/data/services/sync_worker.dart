import 'package:debts_payment_app/data/local/app_database.dart';
import 'package:debts_payment_app/data/mock/mock_debt_api.dart';

class SyncWorker {
  SyncWorker({
    required this._database,
    required this._api,
  });

  final AppDatabase _database;
  final MockDebtApi _api;

  bool _isSyncing = false;

  Future<void> syncPendingPayments() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = await _database.database;

      await db.update(
        'sync_queue',
        {
          'status': 'pending',
          'last_error': 'Retry after app restart',
        },
        where: 'status = ?',
        whereArgs: ['syncing'],
      );

      final operations = await db.query(
        'sync_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'device_id ASC, device_sequence ASC',
      );

      for (final operation in operations) {
        await _syncOne(operation);
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncOne(Map<String, Object?> operation) async {
    final db = await _database.database;
    final operationId = operation['operation_id'] as String;
    final paymentId = operation['payment_id'] as String;

    await db.update(
      'sync_queue',
      {'status': 'syncing', 'last_error': null},
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );

    try {
      final payments = await db.query(
        'payments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );

      if (payments.isEmpty) {
        await _markConflict(
          operationId: operationId,
          paymentId: paymentId,
          reason: 'Payment record is missing locally.',
        );
        return;
      }

      final payment = payments.single;

      await _api.submitPayment(
        operationId: operationId,
        customerId: payment['customer_id'] as String,
        deviceId: operation['device_id'] as String,
        deviceSequence: operation['device_sequence'] as int,
        amount: payment['amount'] as int,
      );

      await db.transaction((txn) async {
        await txn.update(
          'sync_queue',
          {'status': 'confirmed', 'last_error': null},
          where: 'operation_id = ?',
          whereArgs: [operationId],
        );

        await txn.update(
          'payments',
          {'status': 'confirmed'},
          where: 'id = ?',
          whereArgs: [paymentId],
        );
      });
    } on MockResponseLost {
      await db.update(
        'sync_queue',
        {
          'status': 'pending',
          'last_error': 'Response lost; safe to retry with the same operation ID.',
        },
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    } on MockPaymentConflict catch (error) {
      await _markConflict(
        operationId: operationId,
        paymentId: paymentId,
        reason: error.toString(),
      );
    } catch (error) {
      await db.update(
        'sync_queue',
        {'status': 'pending', 'last_error': error.toString()},
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    }
  }

  Future<void> _markConflict({
    required String operationId,
    required String paymentId,
    required String reason,
  }) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      await txn.update(
        'sync_queue',
        {'status': 'conflict', 'last_error': reason},
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );

      await txn.update(
        'payments',
        {'status': 'conflict'},
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    });
  }
}