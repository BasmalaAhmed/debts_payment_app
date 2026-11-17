import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:debts_payment_app/data/local/app_database.dart';
import 'package:debts_payment_app/data/mock/mock_debt_api.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/data/services/sync_worker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('allocates locally and survives database reopen', (_) async {
    final customerId = _newCustomerId();
    const deviceId = 'emulator-device';

    final database = AppDatabase.instance;
    final repository = PaymentRepo(database: database);
    final api = MockDebtApi();

    await _seedLocalDebts(api, repository, customerId);

    final paymentId = await repository.recordPayment(
      customerId: customerId,
      amount: 120000,
      deviceId: deviceId,
    );

    final db = await database.database;
    final allocations = await db.query(
      'payment_allocations',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
      orderBy: 'debt_id ASC',
    );

    expect(allocations, hasLength(2));
    expect(allocations[0]['amount'], 100000);
    expect(allocations[1]['amount'], 20000);

    final debtBalances = await repository.getDebtBalances(customerId);

    expect(debtBalances.map((debt) => debt.localOutstanding).toList(), [
      0,
      30000,
    ]);

    await expectLater(
      repository.recordPayment(
        customerId: customerId,
        amount: 31000,
        deviceId: deviceId,
      ),
      throwsA(isA<StateError>()),
    );

    await database.close();
    final reopenedDb = await database.database;
    final savedPayment = await reopenedDb.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );

    expect(savedPayment, hasLength(1));
    expect(savedPayment.single['status'], 'local');
  });

  testWidgets('lost response can be retried without duplicate collection', (
    _,
  ) async {
    final customerId = _newCustomerId();
    const deviceId = 'emulator-device';

    final database = AppDatabase.instance;
    final repository = PaymentRepo(database: database);
    final api = MockDebtApi();

    await _seedLocalDebts(api, repository, customerId);

    final paymentId = await repository.recordPayment(
      customerId: customerId,
      amount: 20000,
      deviceId: deviceId,
    );

    final db = await database.database;
    final queueRows = await db.query(
      'sync_queue',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
    );
    final operationId = queueRows.single['operation_id'] as String;

    api.loseNextResponseFor(operationId);
    final worker = SyncWorker(database: database, api: api);

    await worker.syncPendingPayments();

    var paymentRows = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    expect(paymentRows.single['status'], 'local');
    expect(await _serverBalance(api, customerId), 130000);

    await worker.syncPendingPayments();

    paymentRows = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    expect(paymentRows.single['status'], 'confirmed');
    expect(await _serverBalance(api, customerId), 130000);
  });

  testWidgets('server conflict keeps the local payment for review', (_) async {
    final customerId = _newCustomerId();
    const deviceId = 'emulator-device';

    final database = AppDatabase.instance;
    final repository = PaymentRepo(database: database);
    final api = MockDebtApi();

    await _seedLocalDebts(api, repository, customerId);

    await api.simulateOtherDevicePayment(customerId: customerId, amount: 50000);

    final paymentId = await repository.recordPayment(
      customerId: customerId,
      amount: 120000,
      deviceId: deviceId,
    );

    final worker = SyncWorker(database: database, api: api);
    await worker.syncPendingPayments();

    final db = await database.database;
    final paymentRows = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    final queueRows = await db.query(
      'sync_queue',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
    );

    expect(paymentRows.single['amount'], 120000);
    expect(paymentRows.single['status'], 'conflict');
    expect(queueRows.single['status'], 'conflict');
    expect(queueRows.single['last_error'], contains('100000'));
    expect(await _serverBalance(api, customerId), 100000);
  });

  testWidgets('device ID remains stable after database reopen', (_) async {
    final database = AppDatabase.instance;
    final repository = PaymentRepo(database: database);

    final firstDeviceId = await repository.getOrCreateDeviceId();

    await database.close();

    final reopenedDeviceId = await repository.getOrCreateDeviceId();

    expect(firstDeviceId, isNotEmpty);
    expect(reopenedDeviceId, firstDeviceId);
  });

  testWidgets('in-flight payment recovers after database reopen', (_) async {
    final customerId = _newCustomerId();
    const deviceId = 'emulator-device';

    final database = AppDatabase.instance;
    final repository = PaymentRepo(database: database);
    final api = MockDebtApi();

    await _seedLocalDebts(api, repository, customerId);

    final paymentId = await repository.recordPayment(
      customerId: customerId,
      amount: 20000,
      deviceId: deviceId,
    );

    final db = await database.database;
    final queueRows = await db.query(
      'sync_queue',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    final operation = queueRows.single;

    final paymentRows = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    final payment = paymentRows.single;
    final operationId = operation['operation_id'] as String;

    api.loseNextResponseFor(operationId);
    await expectLater(
      api.submitPayment(
        operationId: operationId,
        customerId: customerId,
        deviceId: operation['device_id'] as String,
        deviceSequence: operation['device_sequence'] as int,
        amount: payment['amount'] as int,
      ),
      throwsA(isA<MockResponseLost>()),
    );

    await db.update(
      'sync_queue',
      {'status': 'syncing'},
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );

    await database.close();
    await api.close();

    final restartedApi = MockDebtApi();
    final worker = SyncWorker(database: database, api: restartedApi);
    await worker.syncPendingPayments();

    final reopenedDb = await database.database;
    final savedPayment = await reopenedDb.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    final savedOperation = await reopenedDb.query(
      'sync_queue',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );

    expect(savedPayment.single['status'], 'confirmed');
    expect(savedOperation.single['status'], 'confirmed');
    expect(await _serverBalance(restartedApi, customerId), 130000);
  });
}

String _newCustomerId() {
  return 'integration-${DateTime.now().microsecondsSinceEpoch}';
}

Future<void> _seedLocalDebts(
  MockDebtApi api,
  PaymentRepo repo,
  String customerId,
) async {
  final serverDebts = await api.fetchDebts(customerId);
  await repo.cacheDebts(customerId, serverDebts);
}

Future<int> _serverBalance(MockDebtApi api, String customerId) async {
  final debts = await api.fetchDebts(customerId);

  return debts.fold<int>(
    0,
    (total, debt) => total + (debt['server_outstanding'] as int),
  );
}
