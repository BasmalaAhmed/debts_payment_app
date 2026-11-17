import 'package:debts_payment_app/data/local/models/debt_balance.dart';
import 'package:debts_payment_app/data/mock/mock_debt_api.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/features/customer/widgets/debt_card.dart';
import 'package:debts_payment_app/features/customer/widgets/dept_summary_card.dart';
import 'package:flutter/material.dart';

class CustomerDebtScreen extends StatefulWidget {
  const CustomerDebtScreen({
    super.key,
    required this.customerId,
    required this.repository,
    required this.api,
  });

  final String customerId;
  final PaymentRepo repository;
  final MockDebtApi api;

  @override
  State<CustomerDebtScreen> createState() => _CustomerDebtScreenState();
}

class _CustomerDebtScreenState extends State<CustomerDebtScreen> {
  List<DebtBalance> _debts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDebts();
  }

  Future<void> _loadDebts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      var debts = await widget.repository.getDebtBalances(widget.customerId);

      if (debts.isEmpty) {
        final serverDebts = await widget.api.fetchDebts(widget.customerId);
        await widget.repository.cacheDebts(widget.customerId, serverDebts);
        debts = await widget.repository.getDebtBalances(widget.customerId);
      }

      if (!mounted) return;
      setState(() {
        _debts = debts;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localTotal = _debts.fold<int>(
      0,
      (total, debt) => total + debt.localOutstanding,
    );

    return Scaffold(
      backgroundColor: Color(0XFF52796F),
      appBar: AppBar(
        backgroundColor: Color(0XFF52796F),
        foregroundColor: Colors.white,
        title: const Text('مديونيات العميل'),
        actions: [
          IconButton(
            onPressed: _loadDebts,
            tooltip: 'إعادة تحميل البيانات المحلية',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(localTotal),
    );
  }

  Widget _buildBody(int localTotal) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('حدث خطأ أثناء تحميل المديونيات:\n$_error'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadDebts,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_debts.isEmpty) {
      return const Center(child: Text('لا يوجد مديونيات مسجلة للعميل.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DeptSummaryCard(localTotal: localTotal),
        const SizedBox(height: 12),
        for (var index = 0; index < _debts.length; index++)
          DebtCard(number: index + 1, debt: _debts[index]),
      ],
    );
  }
}
