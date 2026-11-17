import 'package:debts_payment_app/core/formatters/egp_formatter.dart';
import 'package:debts_payment_app/data/local/models/debt_balance.dart';
import 'package:flutter/material.dart';

class DebtCard extends StatelessWidget {
  const DebtCard({super.key, required this.number, required this.debt});

  final int number;
  final DebtBalance debt;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Color(0XFFD5F9DE),
      child: ListTile(
        title: Text(
          'مديونية $number',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'رصيد السيرفر المحفوظ: '
          '${formatEgp(debt.serverOutstanding)}\n'
          'المتبقي محليًا: '
          '${formatEgp(debt.localOutstanding)}',
          style: TextStyle(fontSize: 16),
        ),
        isThreeLine: true,
      ),
    );
  }
}
