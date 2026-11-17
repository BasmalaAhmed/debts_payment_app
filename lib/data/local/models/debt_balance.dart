class DebtBalance {
  const DebtBalance({
    required this.debtId,
    required this.serverOutstanding,
    required this.localOutstanding,
    required this.createdAt,
  });

  final String debtId;
  final int serverOutstanding;
  final int localOutstanding;
  final DateTime createdAt;
}