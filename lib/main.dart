import 'package:debts_payment_app/app/main_navigation_shell.dart';
import 'package:debts_payment_app/core/theme/app_theme.dart';
import 'package:debts_payment_app/data/local/app_database.dart';
import 'package:debts_payment_app/data/mock/mock_debt_api.dart';
import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/data/services/device_connectivity_observer.dart';
import 'package:debts_payment_app/data/services/sync_worker.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase.instance;
  final network = MockNetwork();
  final connectivityObserver = DeviceConnectivityObserver(network: network);

  await connectivityObserver.start();

  final api = MockDebtApi(network: network);
  final repository = PaymentRepo(database: database);
  final syncWorker = SyncWorker(database: database, api: api);
  await syncWorker.recoverInterrupted();

  runApp(
    DebtPaymentApp(
      api: api,
      repository: repository,
      syncWorker: syncWorker,
      network: network,
      connectivityObserver: connectivityObserver,
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
    required this.connectivityObserver,
  });

  final MockDebtApi api;
  final PaymentRepo repository;
  final SyncWorker syncWorker;
  final MockNetwork network;
  final DeviceConnectivityObserver connectivityObserver;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تحصيل الأقساط',
      theme: AppTheme.lightTheme,
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
        connectivityObserver: connectivityObserver,
      ),
    );
  }
}
