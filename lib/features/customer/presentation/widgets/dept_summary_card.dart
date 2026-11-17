import 'package:debts_payment_app/core/formatters/egp_formatter.dart';
import 'package:flutter/material.dart';

class DeptSummaryCard extends StatelessWidget {
  const DeptSummaryCard({super.key, required this.localTotal});
  final int localTotal;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Color(0XFFCAD2C5),
      child: ListTile(
        title: const Text(
          'إجمالي المتبقي على الجهاز',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'يشمل التحصيلات المحلية والمعلقة',
          style: TextStyle(fontSize: 14),
        ),
        trailing: Text(
          formatEgp(localTotal),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
