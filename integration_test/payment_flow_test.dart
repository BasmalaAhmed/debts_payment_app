import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:debts_payment_app/data/local/app_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('payment allocation persists and overpayment is rejected', (
    tester,
  ) async {
    const customerId = 'integration-test-customer';
    const deviceId = 'integration-test-device';

    final appDatabase = AppDatabase.instance;
    final db = await appDatabase.database;

    await appDatabase.replaceDebts(customerId, [
      {
        'id': 'integration-debt-001',
        'customer_id': customerId,
        'original_amount': 100000,
        'server_outstanding': 100000,
        'created_at': '2026-01-01T00:00:00.000Z',
      },
      {
        'id': 'integration-debt-002',
        'customer_id': customerId,
        'original_amount': 50000,
        'server_outstanding': 50000,
        'created_at': '2026-02-01T00:00:00.000Z',
      },
    ]);

    final repository = PaymentRepo(database: appDatabase);

    final paymentId = await repository.recordPayment(
      customerId: customerId,
      amount: 120000,
      deviceId: deviceId,
    );

    final allocations = await db.query(
      'payment_allocations',
      where: 'payment_id = ?',
      whereArgs: [paymentId],
      orderBy: 'debt_id ASC',
    );

    expect(allocations, hasLength(2));
    expect(allocations[0]['amount'], 100000);
    expect(allocations[1]['amount'], 20000);

    await expectLater(
      repository.recordPayment(
        customerId: customerId,
        amount: 31000,
        deviceId: deviceId,
      ),
      throwsA(isA<StateError>()),
    );

    final paymentsBeforeReopen = await db.query(
      'payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
    expect(paymentsBeforeReopen, hasLength(1));

    await appDatabase.close();
    final reopenedDb = await appDatabase.database;

    final savedPayment = await reopenedDb.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );

    expect(savedPayment, hasLength(1));
    expect(savedPayment.single['status'], 'local');
  });
}
