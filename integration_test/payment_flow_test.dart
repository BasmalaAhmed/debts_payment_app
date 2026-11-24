import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:debts_payment_app/data/services/sync_on_reconnect.dart';
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

    var queueAfterLoss = await db.query(
      'sync_queue',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    expect(queueAfterLoss.single['status'], 'pending');
    expect(queueAfterLoss.single['outcome_unknown'], 1);
    expect(queueAfterLoss.single['already_processed'], 0);

    await worker.syncPendingPayments();

    paymentRows = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    expect(paymentRows.single['status'], 'confirmed');
    expect(await _serverBalance(api, customerId), 130000);

    queueAfterLoss = await db.query(
      'sync_queue',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    expect(queueAfterLoss.single['status'], 'confirmed');
    expect(queueAfterLoss.single['outcome_unknown'], 0);
    expect(queueAfterLoss.single['already_processed'], 1);
    expect(queueAfterLoss.single['confirmed_at'], isNotNull);

    expect(await api.countServerOperations(operationId), 1);
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
    expect(queueRows.single['conflict_server_balance'], 100000);
    expect(queueRows.single['conflict_other_device'], 'B2');
    expect(queueRows.single['conflict_other_amount'], 50000);
    expect(queueRows.single['outcome_unknown'], 0);
    expect(queueRows.single['expected_server_version'], 1);
    expect(queueRows.single['last_error'], contains('Server version changed'));
    expect(queueRows.single['last_error'], contains('100000'));
    expect(await _serverBalance(api, customerId), 100000);
  });

  testWidgets('cancelling a conflict keeps the record and syncs the balance', (
    _,
  ) async {
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
    await SyncWorker(database: database, api: api).syncPendingPayments();

    final db = await database.database;
    final queue = await db.query(
      'sync_queue',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
    );
    final operationId = queue.single['operation_id'] as String;
    expect(queue.single['status'], 'conflict');

    await repository.cancelConflictedPayment(
      operationId: operationId,
      serverDebts: await api.fetchDebts(customerId),
    );

    final payment = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    final queueAfter = await db.query(
      'sync_queue',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );

    expect(payment.single['status'], 'cancelled');
    expect(payment.single['amount'], 120000);
    expect(queueAfter.single['status'], 'cancelled');
    expect(queueAfter.single['resolved_at'], isNotNull);

    final balances = await repository.getDebtBalances(customerId);
    expect(balances.fold<int>(0, (t, d) => t + d.localOutstanding), 100000);
  });

  testWidgets(
    'replacing a conflict creates a new operation and keeps the old',
    (_) async {
      final customerId = _newCustomerId();
      const deviceId = 'emulator-device';

      final database = AppDatabase.instance;
      final repository = PaymentRepo(database: database);
      final api = MockDebtApi();

      await _seedLocalDebts(api, repository, customerId);
      await api.simulateOtherDevicePayment(
        customerId: customerId,
        amount: 50000,
      );

      final oldPaymentId = await repository.recordPayment(
        customerId: customerId,
        amount: 120000,
        deviceId: deviceId,
      );
      final worker = SyncWorker(database: database, api: api);
      await worker.syncPendingPayments();

      final db = await database.database;
      final oldQueue = (await db.query(
        'sync_queue',
        where: 'payment_id = ?',
        whereArgs: [oldPaymentId],
      )).single;
      final oldOperationId = oldQueue['operation_id'] as String;
      final oldSequence = oldQueue['device_sequence'] as int;

      final newPaymentId = await repository.replaceConflictedPayment(
        operationId: oldOperationId,
        serverDebts: await api.fetchDebts(customerId),
      );

      final oldPayment = (await db.query(
        'payments',
        where: 'id = ?',
        whereArgs: [oldPaymentId],
      )).single;
      final oldQueueAfter = (await db.query(
        'sync_queue',
        where: 'operation_id = ?',
        whereArgs: [oldOperationId],
      )).single;
      expect(oldPayment['amount'], 120000);
      expect(oldPayment['status'], 'superseded');
      expect(oldQueueAfter['status'], 'superseded');

      final newPayment = (await db.query(
        'payments',
        where: 'id = ?',
        whereArgs: [newPaymentId],
      )).single;
      final newQueue = (await db.query(
        'sync_queue',
        where: 'payment_id = ?',
        whereArgs: [newPaymentId],
      )).single;
      expect(newPayment['amount'], 100000);
      expect(newQueue['operation_id'], isNot(oldOperationId));
      expect(newQueue['device_sequence'], oldSequence + 1);
      expect(
        oldQueueAfter['replaced_by_sequence'],
        newQueue['device_sequence'],
      );
      expect(newQueue['replaces_sequence'], oldSequence);
      expect(newQueue['status'], 'pending');

      await worker.syncPendingPayments();
      final confirmed = (await db.query(
        'sync_queue',
        where: 'payment_id = ?',
        whereArgs: [newPaymentId],
      )).single;
      expect(confirmed['status'], 'confirmed');
      expect(await _serverBalance(api, customerId), 0);
    },
  );

  testWidgets(
    'resolving a conflict is blocked while another op is unconfirmed',
    (_) async {
      final customerId = _newCustomerId();
      const deviceId = 'emulator-device';

      final database = AppDatabase.instance;
      final repository = PaymentRepo(database: database);
      final api = MockDebtApi();

      await _seedLocalDebts(api, repository, customerId);
      await api.simulateOtherDevicePayment(
        customerId: customerId,
        amount: 50000,
      );

      final conflictedId = await repository.recordPayment(
        customerId: customerId,
        amount: 120000,
        deviceId: deviceId,
      );
      await SyncWorker(database: database, api: api).syncPendingPayments();

      final secondId = await repository.recordPayment(
        customerId: customerId,
        amount: 10000,
        deviceId: deviceId,
      );
      final db = await database.database;
      await db.update(
        'sync_queue',
        {'outcome_unknown': 1},
        where: 'payment_id = ?',
        whereArgs: [secondId],
      );

      final operationId =
          (await db.query(
                'sync_queue',
                where: 'payment_id = ?',
                whereArgs: [conflictedId],
              )).single['operation_id']
              as String;

      await expectLater(
        repository.cancelConflictedPayment(
          operationId: operationId,
          serverDebts: await api.fetchDebts(customerId),
        ),
        throwsA(isA<ConflictResolutionBlocked>()),
      );
      final stillConflict = await db.query(
        'sync_queue',
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
      expect(stillConflict.single['status'], 'conflict');
    },
  );

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
    expect(savedOperation.single['already_processed'], 1);
    expect(savedOperation.single['outcome_unknown'], 0);
    expect(await _serverBalance(restartedApi, customerId), 130000);
  });

  testWidgets('payment and allocations roll back if queue insert fails', (
    _,
  ) async {
    final customerId = _newCustomerId();
    const deviceId = 'emulator-device';
    const triggerName = 'force_sync_queue_insert_failure';

    final database = AppDatabase.instance;
    final repository = PaymentRepo(database: database);
    final api = MockDebtApi();

    await _seedLocalDebts(api, repository, customerId);

    final db = await database.database;
    final queueCountBefore = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue',
    );
    final previousQueueCount = queueCountBefore.single['total'] as int;

    await db.execute('''
    CREATE TRIGGER $triggerName
    BEFORE INSERT ON sync_queue
    BEGIN
      SELECT RAISE(ABORT, 'forced queue insert failure');
    END;
  ''');

    try {
      await expectLater(
        repository.recordPayment(
          customerId: customerId,
          amount: 20000,
          deviceId: deviceId,
        ),
        throwsA(isA<Exception>()),
      );
    } finally {
      await db.execute('DROP TRIGGER IF EXISTS $triggerName');
    }

    final payments = await db.query(
      'payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );

    final allocations = await db.query(
      'payment_allocations',
      where: 'debt_id IN (?, ?)',
      whereArgs: ['$customerId-debt-001', '$customerId-debt-002'],
    );

    final queueCountAfter = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue',
    );

    expect(payments, isEmpty);
    expect(allocations, isEmpty);
    expect(queueCountAfter.single['total'], previousQueueCount);
  });

  testWidgets('mock API fails offline and works after reconnect', (_) async {
    final network = MockNetwork(initiallyOnline: false);
    final api = MockDebtApi(network: network);
    const customerId = 'network-test-customer';

    await expectLater(
      api.fetchDebts(customerId),
      throwsA(isA<MockNetworkUnavailable>()),
    );

    network.setOnline(true);

    final debts = await api.fetchDebts(customerId);
    expect(debts, hasLength(2));

    await api.close();
    await network.dispose();
  });

  testWidgets('pending payment syncs automatically after reconnect', (_) async {
    final customerId = _newCustomerId();
    const deviceId = 'emulator-device';

    final network = MockNetwork();
    final api = MockDebtApi(network: network);
    final database = AppDatabase.instance;
    final repository = PaymentRepo(database: database);

    await _seedLocalDebts(api, repository, customerId);

    final paymentId = await repository.recordPayment(
      customerId: customerId,
      amount: 20000,
      deviceId: deviceId,
    );

    final worker = SyncWorker(database: database, api: api);

    network.setOnline(false);
    await worker.syncPendingPayments();

    final db = await database.database;
    var payment = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    expect(payment.single['status'], 'local');

    final reconnectSync = SyncOnReconnect(network: network, syncWorker: worker);
    final syncFinished = reconnectSync.syncCompleted.first;

    network.setOnline(true);
    await syncFinished.timeout(const Duration(seconds: 5));

    payment = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );

    expect(payment.single['status'], 'confirmed');
    expect(await _serverBalance(api, customerId), 130000);

    await reconnectSync.dispose();
    await api.close();
    await network.dispose();
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
