import 'package:debts_payment_app/core/formatters/egp_formatter.dart';
import 'package:debts_payment_app/data/local/models/sync_operation.dart';
import 'package:flutter/material.dart';

class SyncOperationCard extends StatelessWidget {
  const SyncOperationCard({super.key, required this.operation});

  final SyncOperation operation;

  @override
  Widget build(BuildContext context) {
    final status = _statusLabel(operation.syncStatus);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: Color(0XFFD5F9DE),
      child: ListTile(
        title: Text('تحصيل ${formatEgp(operation.amount)}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('رقم العملية: ${operation.deviceSequence}'),
            const SizedBox(height: 4),
            Text(status.label),
            if (operation.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                operation.lastError!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ],
        ),
        isThreeLine: operation.lastError != null,
      ),
    );
  }

  ({String label, Color color}) _statusLabel(String status) {
    return switch (status) {
      'pending' => (label: 'منتظر المزامنة', color: Colors.orange),
      'syncing' => (label: 'جاري الإرسال', color: Colors.blue),
      'confirmed' => (label: 'تم تأكيد التحصيل', color: Colors.green),
      'conflict' => (label: 'يحتاج الى مراجعة', color: Colors.red),
      _ => (label: 'حالة غير معروفة: $status', color: Colors.grey),
    };
  }
}
