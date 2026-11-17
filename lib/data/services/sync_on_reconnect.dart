// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:debts_payment_app/data/mock/mock_network.dart';
import 'package:debts_payment_app/data/services/sync_worker.dart';

class SyncOnReconnect {
  SyncOnReconnect({
    required MockNetwork network,
    required SyncWorker syncWorker,
    void Function(Object error)? onError,
  }) : _network = network,
       _syncWorker = syncWorker,
       _onError = onError {
    _subscription = _network.changes.listen((isOnline) {
      if (isOnline) {
        unawaited(_runSync());
      }
    });

    if (_network.isOnline) {
      unawaited(_runSync());
    }
  }

  final MockNetwork _network;
  final SyncWorker _syncWorker;
  final void Function(Object error)? _onError;
  final StreamController<void> _syncCompleted =
      StreamController<void>.broadcast();

  late final StreamSubscription<bool> _subscription;
  bool _isSyncing = false;

  Stream<void> get syncCompleted => _syncCompleted.stream;

  Future<void> _runSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      await _syncWorker.syncPendingPayments();
    } catch (error) {
      _onError?.call(error);
    } finally {
      _isSyncing = false;
      if (!_syncCompleted.isClosed) {
        _syncCompleted.add(null);
      }
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _syncCompleted.close();
  }
}
