import 'package:debts_payment_app/data/local/app_database.dart';
import 'package:debts_payment_app/data/local/models/debt_balance.dart';
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

  Future<List<DebtBalance>> getDebtBalances(String customerId) async {
    final db = await _database.database;

    final rows = await db.rawQuery(
      '''
    SELECT
      d.id AS debt_id,
      d.server_outstanding AS server_outstanding,
      d.created_at AS created_at,
      d.server_outstanding - COALESCE(
        SUM(
          CASE WHEN p.id IS NOT NULL THEN pa.amount ELSE 0 END
        ),
        0
      ) AS local_outstanding
    FROM debts d
    LEFT JOIN payment_allocations pa
      ON pa.debt_id = d.id
    LEFT JOIN payments p
      ON p.id = pa.payment_id
      AND p.status IN ('local', 'confirmed', 'conflict')
    WHERE d.customer_id = ?
    GROUP BY d.id, d.server_outstanding, d.created_at
    ORDER BY d.created_at ASC, d.id ASC
    ''',
      [customerId],
    );

    return rows.map((row) {
      return DebtBalance(
        debtId: row['debt_id'] as String,
        serverOutstanding: row['server_outstanding'] as int,
        localOutstanding: row['local_outstanding'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }
}
