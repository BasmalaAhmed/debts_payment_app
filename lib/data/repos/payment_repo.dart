import 'package:debts_payment_app/data/local/app_database.dart';
import 'package:debts_payment_app/data/local/models/debt_record.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class PaymentRepo {
  PaymentRepo({required this._database, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Future<String> recordPayment({
    required String customerId,
    required int amount,
    required String deviceId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero');
    }

    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be empty');
    }

    final db = await _database.database;

    return db.transaction((txn) async {
      final debtRows = await txn.query(
        'debts',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at ASC, id ASC',
      );

      final debts = debtRows.map(_debtFromRow).toList();
      final allocations = <({DebtRecord debt, int amount})>[];
      var remainingToAllocate = amount;

      for (final debt in debts) {
        final locallyCollected = await _locallyCollectedForDebt(txn, debt.id);
        final localOutstanding = debt.serverOutstanding - locallyCollected;

        if (localOutstanding <= 0) continue;

        final allocated = remainingToAllocate < localOutstanding
            ? remainingToAllocate
            : localOutstanding;

        allocations.add((debt: debt, amount: allocated));
        remainingToAllocate -= allocated;

        if (remainingToAllocate == 0) break;
      }

      if (remainingToAllocate > 0) {
        throw StateError('Payment exceeds the locally available balance.');
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final paymentId = _uuid.v4();
      final operationId = _uuid.v4();
      final deviceSequence = await _nextDeviceSequence(txn, deviceId);

      await txn.insert('payments', {
        'id': paymentId,
        'customer_id': customerId,
        'amount': amount,
        'status': 'local',
        'created_at': now,
      });

      for (final allocation in allocations) {
        await txn.insert('payment_allocations', {
          'payment_id': paymentId,
          'debt_id': allocation.debt.id,
          'amount': allocation.amount,
        });
      }

      await txn.insert('sync_queue', {
        'operation_id': operationId,
        'device_id': deviceId,
        'device_sequence': deviceSequence,
        'payment_id': paymentId,
        'status': 'pending',
        'last_error': null,
        'created_at': now,
      });

      return paymentId;
    });
  }

  Future<int> _locallyCollectedForDebt(Transaction txn, String debtId) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(pa.amount), 0) AS total
      FROM payment_allocations pa
      JOIN payments p ON p.id = pa.payment_id
      WHERE pa.debt_id = ?
        AND p.status IN ('local', 'confirmed', 'conflict')
      ''',
      [debtId],
    );

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> _nextDeviceSequence(Transaction txn, String deviceId) async {
    final rows = await txn.rawQuery(
      '''
      SELECT MAX(device_sequence) AS last_sequence
      FROM sync_queue
      WHERE device_id = ?
      ''',
      [deviceId],
    );

    final lastSequence = rows.first['last_sequence'] as int?;
    return (lastSequence ?? 0) + 1;
  }

  DebtRecord _debtFromRow(Map<String, Object?> row) {
    return DebtRecord(
      id: row['id'] as String,
      customerId: row['customer_id'] as String,
      serverOutstanding: row['server_outstanding'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Future<void> cacheDebts(String customerId, List<Map<String, Object?>> debts) {
    return _database.replaceDebts(customerId, debts);
  }
}
