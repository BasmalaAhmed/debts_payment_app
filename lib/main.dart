import 'package:debts_payment_app/app/main_navigation_shell.dart';
import 'package:debts_payment_app/data/local/app_database.dart';
import 'package:debts_payment_app/data/mock/mock_debt_api.dart';
import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/data/services/sync_worker.dart';
import 'package:flutter/material.dart';

void main() {
  final database = AppDatabase.instance;
  final network = MockNetwork();
  final api = MockDebtApi();
  final repository = PaymentRepo(database: database);
  final syncWorker = SyncWorker(database: database, api: api);

  runApp(
    DebtPaymentApp(
      api: api,
      repository: repository,
      syncWorker: syncWorker,
      network: network,
    ),
  );
}

class DebtPaymentApp extends StatelessWidget {
  const DebtPaymentApp({
    super.key,
    required this.api,
    required this.repository,
    required this.syncWorker,
    required this.network,
  });

  final MockDebtApi api;
  final PaymentRepo repository;
  final SyncWorker syncWorker;
  final MockNetwork network;

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
      home: MainNavigationShell(
        api: api,
        repository: repository,
        syncWorker: syncWorker,
        network: network,
      ),
    );
  }
}
