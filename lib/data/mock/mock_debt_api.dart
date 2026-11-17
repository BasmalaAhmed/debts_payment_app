import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class MockDebtApi {
  final MockNetwork _network;
  Database? _serverDatabase;
  final Set<String> _operationsWithLostResponses = {};

  MockDebtApi({MockNetwork? network}) : _network = network ?? MockNetwork();

  Future<Database> get _database async {
    final existingDatabase = _serverDatabase;
    if (existingDatabase != null) return existingDatabase;

    final directory = await getDatabasesPath();
    final databasePath = p.join(directory, 'mock_server.db');

    final database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE server_debts (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            original_amount INTEGER NOT NULL,
            outstanding INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE server_operations (
            operation_id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            device_id TEXT NOT NULL,
            device_sequence INTEGER NOT NULL,
            amount INTEGER NOT NULL,
            server_balance_after INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );

    _serverDatabase = database;
    return database;
  }

  void loseNextResponseFor(String operationId) {
    _operationsWithLostResponses.add(operationId);
  }

  Future<List<Map<String, Object?>>> fetchDebts(String customerId) async {
    await _beforeRequest();
    final db = await _database;

    return db.transaction((txn) async {
      await _seedCustomerIfNeeded(txn, customerId);

      final rows = await txn.query(
        'server_debts',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at ASC, id ASC',
      );

      return rows.map((row) {
        return <String, Object?>{
          'id': row['id'],
          'customer_id': row['customer_id'],
          'original_amount': row['original_amount'],
          'server_outstanding': row['outstanding'],
          'created_at': row['created_at'],
        };
      }).toList();
    });
  }

  Future<MockPaymentResult> submitPayment({
    required String operationId,
    required String customerId,
    required String deviceId,
    required int deviceSequence,
    required int amount,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero');
    }

    await _beforeRequest();

    final db = await _database;

    final result = await db.transaction((txn) async {
      await _seedCustomerIfNeeded(txn, customerId);

      final previousOperations = await txn.query(
        'server_operations',
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );

      if (previousOperations.isNotEmpty) {
        final previous = previousOperations.single;
        return MockPaymentResult(
          operationId: operationId,
          serverBalanceAfter: previous['server_balance_after'] as int,
          alreadyProcessed: true,
        );
      }

      final debts = await txn.query(
        'server_debts',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at ASC, id ASC',
      );

      final serverBalance = debts.fold<int>(
        0,
        (total, debt) => total + (debt['outstanding'] as int),
      );

      if (amount > serverBalance) {
        throw MockPaymentConflict(
          requestedAmount: amount,
          serverBalance: serverBalance,
        );
      }

      var remaining = amount;

      for (final debt in debts) {
        if (remaining == 0) break;

        final outstanding = debt['outstanding'] as int;
        if (outstanding == 0) continue;

        final deducted = remaining < outstanding ? remaining : outstanding;

        await txn.update(
          'server_debts',
          {'outstanding': outstanding - deducted},
          where: 'id = ?',
          whereArgs: [debt['id']],
        );

        remaining -= deducted;
      }

      final balanceAfter = serverBalance - amount;

      await txn.insert('server_operations', {
        'operation_id': operationId,
        'customer_id': customerId,
        'device_id': deviceId,
        'device_sequence': deviceSequence,
        'amount': amount,
        'server_balance_after': balanceAfter,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      return MockPaymentResult(
        operationId: operationId,
        serverBalanceAfter: balanceAfter,
        alreadyProcessed: false,
      );
    });

    if (_operationsWithLostResponses.remove(operationId)) {
      throw MockResponseLost(operationId);
    }

    return result;
  }

  Future<void> simulateOtherDevicePayment({
    required String customerId,
    required int amount,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero');
    }

    final db = await _database;

    await db.transaction((txn) async {
      await _seedCustomerIfNeeded(txn, customerId);

      final debts = await txn.query(
        'server_debts',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at ASC, id ASC',
      );

      final serverBalance = debts.fold<int>(
        0,
        (total, debt) => total + (debt['outstanding'] as int),
      );

      if (amount > serverBalance) {
        throw MockPaymentConflict(
          requestedAmount: amount,
          serverBalance: serverBalance,
        );
      }

      var remaining = amount;

      for (final debt in debts) {
        if (remaining == 0) break;

        final outstanding = debt['outstanding'] as int;
        if (outstanding == 0) continue;

        final deducted = remaining < outstanding ? remaining : outstanding;

        await txn.update(
          'server_debts',
          {'outstanding': outstanding - deducted},
          where: 'id = ?',
          whereArgs: [debt['id']],
        );

        remaining -= deducted;
      }
    });
  }

  Future<void> _seedCustomerIfNeeded(Transaction txn, String customerId) async {
    final existingDebts = await txn.query(
      'server_debts',
      columns: ['id'],
      where: 'customer_id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (existingDebts.isNotEmpty) return;

    final now = DateTime.now().toUtc();

    await txn.insert('server_debts', {
      'id': '$customerId-debt-001',
      'customer_id': customerId,
      'original_amount': 100000,
      'outstanding': 100000,
      'created_at': now.subtract(const Duration(days: 60)).toIso8601String(),
    });

    await txn.insert('server_debts', {
      'id': '$customerId-debt-002',
      'customer_id': customerId,
      'original_amount': 50000,
      'outstanding': 50000,
      'created_at': now.subtract(const Duration(days: 30)).toIso8601String(),
    });
  }

  Future<void> close() async {
    final database = _serverDatabase;
    if (database == null) return;

    await database.close();
    _serverDatabase = null;
  }

  Future<void> _beforeRequest() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!_network.isOnline) {
      throw const MockNetworkUnavailable();
    }
  }
}

class MockPaymentResult {
  const MockPaymentResult({
    required this.operationId,
    required this.serverBalanceAfter,
    required this.alreadyProcessed,
  });

  final String operationId;
  final int serverBalanceAfter;
  final bool alreadyProcessed;
}

class MockPaymentConflict implements Exception {
  const MockPaymentConflict({
    required this.requestedAmount,
    required this.serverBalance,
  });

  final int requestedAmount;
  final int serverBalance;

  @override
  String toString() {
    return 'Payment conflict: requested $requestedAmount cents, '
        'but the server balance is $serverBalance cents.';
  }
}

class MockResponseLost implements Exception {
  const MockResponseLost(this.operationId);

  final String operationId;

  @override
  String toString() => 'The response for operation $operationId was lost.';
}
