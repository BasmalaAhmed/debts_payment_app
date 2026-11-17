import 'package:debts_payment_app/core/formatters/egp_formatter.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/available_balance_card.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/payment_amount_field.dart';
import 'package:flutter/material.dart';

class PaymentEntryScreen extends StatefulWidget {
  const PaymentEntryScreen({
    super.key,
    required this.customerId,
    required this.repository,
    required this.availableAmount,
  });

  final String customerId;
  final PaymentRepo repository;
  final int availableAmount;

  @override
  State<PaymentEntryScreen> createState() => _PaymentEntryScreenState();
}

class _PaymentEntryScreenState extends State<PaymentEntryScreen> {
  final _amountController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _savePayment() async {
    if (_isSaving) return;

    final amount = _parseEgpAmount(_amountController.text);

    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'ادخل مبلغًا صحيحًا أكبر من صفر.');
      return;
    }

    if (amount > widget.availableAmount) {
      setState(() {
        _errorMessage =
            'المبلغ أكبر من المتبقي المحلي '
            '(${formatEgp(widget.availableAmount)}).';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final deviceId = await widget.repository.getOrCreateDeviceId();

      await widget.repository.recordPayment(
        customerId: widget.customerId,
        amount: amount,
        deviceId: deviceId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0XFF52796F),
      appBar: AppBar(
        title: const Text('تسجيل تحصيل'),
        backgroundColor: Color(0XFF52796F),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AvailableBalanceCard(availableAmount: widget.availableAmount),
            const SizedBox(height: 16),
            PaymentAmountField(
              controller: _amountController,
              errorMessage: _errorMessage,
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : _savePayment,
              style: FilledButton.styleFrom(
                backgroundColor: Color(0XFFCAD2C5),
                foregroundColor: Colors.black,
              ),
              child: _isSaving
                  ? const CircularProgressIndicator()
                  : const Text(
                      'حفظ التحصيل',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

int? _parseEgpAmount(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;

  final parts = normalized.split('.');
  if (parts.length > 2 || !RegExp(r'^\d+$').hasMatch(parts[0])) {
    return null;
  }

  var fraction = '';
  if (parts.length == 2) {
    fraction = parts[1];
    if (fraction.isNotEmpty && !RegExp(r'^\d{1,2}$').hasMatch(fraction)) {
      return null;
    }
  }

  final pounds = int.tryParse(parts[0]);
  final piastres = int.tryParse(fraction.padRight(2, '0'));

  if (pounds == null || piastres == null) return null;
  return pounds * 100 + piastres;
}
