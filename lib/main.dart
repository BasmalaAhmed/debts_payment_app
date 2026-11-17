import 'package:flutter/material.dart';

import 'data/local/app_database.dart';
import 'data/mock/mock_debt_api.dart';
import 'data/repos/payment_repo.dart';
import 'features/customer/presentation/views/customer_debt_screen.dart';

void main() {
  final api = MockDebtApi();
  final repository = PaymentRepo(database: AppDatabase.instance);

  runApp(DebtPaymentApp(api: api, repository: repository));
}

class DebtPaymentApp extends StatelessWidget {
  const DebtPaymentApp({
    super.key,
    required this.api,
    required this.repository,
  });

  final MockDebtApi api;
  final PaymentRepo repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تحصيل الأقساط',
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: CustomerDebtScreen(
        customerId: 'customer-001',
        repository: repository,
        api: api,
      ),
    );
  }
}
