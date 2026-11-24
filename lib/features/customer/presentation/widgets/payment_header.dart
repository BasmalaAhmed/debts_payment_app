import 'package:debts_payment_app/core/theme/app_colors.dart';
import 'package:debts_payment_app/core/theme/app_styles.dart';
import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class PaymentHeader extends StatelessWidget {
  const PaymentHeader({super.key, required this.title, required this.network});

  final String title;
  final MockNetwork network;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_forward),
                tooltip: 'رجوع',
              ),
              Expanded(child: Text(title, style: AppStyles.screenTitle)),
              StreamBuilder<bool>(
                initialData: network.isOnline,
                stream: network.changes,
                builder: (context, snapshot) {
                  final online = snapshot.data ?? true;
                  if (online) return const SizedBox.shrink();
                  return const StatusBadge(
                    text: 'بدون اتصال',
                    tone: BadgeTone.dark,
                    icon: Icons.wifi_off_rounded,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
