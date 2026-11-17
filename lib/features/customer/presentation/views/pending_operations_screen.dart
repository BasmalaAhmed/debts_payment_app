import 'dart:async';

import 'package:debts_payment_app/data/local/models/sync_operation.dart';
import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:debts_payment_app/data/repos/payment_repo.dart';
import 'package:debts_payment_app/data/services/sync_on_reconnect.dart';
import 'package:debts_payment_app/data/services/sync_worker.dart';
import 'package:debts_payment_app/features/customer/presentation/widgets/sync_operation_card.dart';
import 'package:flutter/material.dart';

class PendingOperationsScreen extends StatefulWidget {
  const PendingOperationsScreen({
    super.key,
    required this.repository,
    required this.syncWorker,
    required this.network,
    required this.syncOnReconnect,
  });

  final PaymentRepo repository;
  final SyncWorker syncWorker;
  final MockNetwork network;
  final SyncOnReconnect syncOnReconnect;

  @override
  State<PendingOperationsScreen> createState() =>
      _PendingOperationsScreenState();
}

class _PendingOperationsScreenState extends State<PendingOperationsScreen> {
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _error;
  List<SyncOperation> _operations = [];

  late final StreamSubscription<void> _syncSubscription;

  @override
  void initState() {
    super.initState();

    _syncSubscription = widget.syncOnReconnect.syncCompleted.listen((_) {
      _loadOperations(showLoading: false);
    });

    _loadOperations();
  }

  @override
  void dispose() {
    _syncSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadOperations({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final operations = await widget.repository.getSyncOperations();

      if (!mounted) return;
      setState(() {
        _operations = operations;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
      _error = null;
    });

    try {
      await widget.syncWorker.syncPendingPayments();
      await _loadOperations(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPendingOperations = _operations.any(
      (operation) => operation.syncStatus == 'pending',
    );

    return Scaffold(
      backgroundColor: Color(0XFF52796F),
      appBar: AppBar(
        backgroundColor: Color(0XFF52796F),
        foregroundColor: Colors.white,
        title: const Text('عمليات التحصيل',),
        actions: [
          IconButton(
            onPressed: _isSyncing ? null : _syncNow,
            tooltip: 'زامن الآن',
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: widget.network.isOnline
                ? 'اقطع الاتصال التجريبي'
                : 'أعد الاتصال التجريبي',
            onPressed: () {
              widget.network.setOnline(!widget.network.isOnline);
              setState(() {});
            },
            icon: Icon(widget.network.isOnline ? Icons.wifi : Icons.wifi_off),
          ),
        ],
      ),
      body: _buildBody(hasPendingOperations),
    );
  }

  Widget _buildBody(bool hasPendingOperations) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _operations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('حصل خطأ أثناء تحميل العمليات:\n$_error'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadOperations,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_operations.isEmpty) {
      return const Center(child: Text('لا يوجد عمليات تحصيل حتى الان'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Color(0XFFCAD2C5),
              disabledBackgroundColor: Color(0XFFCAD2C5).withValues(alpha: 0.5),
            ),
            onPressed: _isSyncing || !hasPendingOperations ? null : _syncNow,
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, color: Color(0XFF52796F)),
            label: Text(
              _isSyncing ? 'جاري المزامنة' : 'زامن الآن',
              style: TextStyle(color: Color(0XFF52796F)),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 12),
        for (final operation in _operations)
          SyncOperationCard(operation: operation),
      ],
    );
  }
}
