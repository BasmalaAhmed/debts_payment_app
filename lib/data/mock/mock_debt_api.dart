class MockDebtApi {
  Future<List<Map<String, Object?>>> fetchDebts(String customerId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final now = DateTime.now().toUtc();

    return [
      {
        'id': 'debt-001',
        'customer_id': customerId,
        'original_amount': 100000,
        'server_outstanding': 100000,
        'created_at': now.subtract(const Duration(days: 60)).toIso8601String(),
      },
      {
        'id': 'debt-002',
        'customer_id': customerId,
        'original_amount': 50000,
        'server_outstanding': 50000,
        'created_at': now.subtract(const Duration(days: 30)).toIso8601String(),
      },
    ];
  }
}