import 'package:debts_payment_app/data/local/models/debt_balance.dart';
import 'package:debts_payment_app/data/mock/mock_debt_api.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/features/customer/presentation/views/payment_entry_screen.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/debt_card.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/dept_summary_card.dart';
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

  Future<void> _openPaymentEntry() async {
    final availableAmount = _debts.fold<int>(
      0,
      (total, debt) => total + debt.localOutstanding,
    );

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaymentEntryScreen(
          customerId: widget.customerId,
          repository: widget.repository,
          availableAmount: availableAmount,
        ),
      ),
    );

    if (saved == true && mounted) {
      await _loadDebts();
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
            tooltip: 'إعادة تحميل البيانات',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _debts.isEmpty || _isLoading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openPaymentEntry,
              icon: const Icon(Icons.payments_outlined, color: Colors.black),
              label: const Text(
                'تسجيل تحصيل',
                style: TextStyle(color: Colors.black),
              ),
              backgroundColor: Color(0XFFCAD2C5),
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
