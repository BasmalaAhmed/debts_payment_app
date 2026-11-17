import 'dart:async';

import 'package:debts_payment_app/data/mock/mock_debt_api.dart';
import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/data/services/sync_on_reconnect.dart';
import 'package:debts_payment_app/data/services/sync_worker.dart';
import 'package:debts_payment_app/features/customer/presentation/views/customer_debt_screen.dart';
import 'package:debts_payment_app/features/customer/presentation/views/pending_operations_screen.dart';
import 'package:flutter/material.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({
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
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late final SyncOnReconnect _syncOnReconnect;

  @override
  void initState() {
    super.initState();
    _syncOnReconnect = SyncOnReconnect(
      network: widget.network,
      syncWorker: widget.syncWorker,
    );
  }

  @override
  void dispose() {
    unawaited(_syncOnReconnect.dispose());
    super.dispose();
  }

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedIndex == 0
          ? CustomerDebtScreen(
              customerId: 'customer-001',
              repository: widget.repository,
              api: widget.api,
            )
          : PendingOperationsScreen(
              repository: widget.repository,
              syncWorker: widget.syncWorker,
              network: widget.network,
              syncOnReconnect: _syncOnReconnect,
            ),
      bottomNavigationBar: NavigationBar(
        indicatorColor: Color(0XFF52796F).withValues(alpha: 0.15),
        backgroundColor: Color(0XFFCAD2C5),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.account_balance_wallet_outlined,
              color: Color(0XFF52796F),
            ),
            label: 'المديونيات',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync, color: Color(0XFF52796F)),
            label: 'عمليات التحصيل',
          ),
        ],
      ),
    );
  }
}
