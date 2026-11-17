import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debts_payment_app/data/local/app_database.dart';
import 'package:debts_payment_app/data/local/models/debt_balance.dart';
import 'package:debts_payment_app/data/mock/mock_debt_api.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/features/customer/customer_debt_screen.dart';

void main() {
  testWidgets('shows customer debt balances', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: CustomerDebtScreen(
          customerId: 'widget-test-customer',
          repository: _FakePaymentRepo(),
          api: MockDebtApi(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('مديونيات العميل'), findsOneWidget);
    expect(find.text('إجمالي المتبقي على الجهاز'), findsOneWidget);
    expect(find.text('1500.00 ج.م'), findsOneWidget);
    expect(find.text('مديونية 1'), findsOneWidget);
    expect(find.text('مديونية 2'), findsOneWidget);
  });
}

class _FakePaymentRepo extends PaymentRepo {
  _FakePaymentRepo() : super(database: AppDatabase.instance);

  @override
  Future<List<DebtBalance>> getDebtBalances(String customerId) async {
    return [
      DebtBalance(
        debtId: 'debt-001',
        serverOutstanding: 100000,
        localOutstanding: 100000,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      DebtBalance(
        debtId: 'debt-002',
        serverOutstanding: 50000,
        localOutstanding: 50000,
        createdAt: DateTime.utc(2026, 2, 1),
      ),
    ];
  }
}