import 'package:debts_payment_app/core/customers/customer_info.dart';
import 'package:debts_payment_app/core/theme/app_styles.dart';
import 'package:debts_payment_app/data/local/models/debt_balance.dart';
import 'package:debts_payment_app/data/local/models/sync_operation.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/debt_card.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/dept_summary_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CustomerDebtContent extends StatelessWidget {
  const CustomerDebtContent({
    super.key,
    required this.info,
    required this.debts,
    this.conflictOp,
    required this.onRefresh,
    this.onDebugLongPress,
  });

  final CustomerInfo info;
  final List<DebtBalance> debts;
  final SyncOperation? conflictOp;
  final Future<void> Function() onRefresh;
  final VoidCallback? onDebugLongPress;

  @override
  Widget build(BuildContext context) {
    final localTotal = debts.fold<int>(0, (t, d) => t + d.localOutstanding);
    final pendingTotal = debts.fold<int>(0, (t, d) => t + d.pendingAmount);
    final serverConfirmedTotal = debts.fold<int>(
      0,
      (t, d) => t + d.serverConfirmedOutstanding,
    );
    final hasConfirmed = debts.any((d) => d.confirmedAmount > 0);

    return RefreshIndicator(
      onRefresh: () async => onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          DeptSummaryCard(
            customerFirstName: info.firstName,
            localTotal: localTotal,
            serverTotal:
                conflictOp?.conflictServerBalance ?? serverConfirmedTotal,
            pendingTotal: pendingTotal,
            conflictOp: conflictOp,
            hasConfirmed: hasConfirmed,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onLongPress: kDebugMode ? onDebugLongPress : null,
            child: const Text(
              'المديونيات · الأقدم أولاً',
              style: AppStyles.sectionHeader,
            ),
          ),
          const SizedBox(height: 10),
          DebtCard(debts: debts),
        ],
      ),
    );
  }
}
