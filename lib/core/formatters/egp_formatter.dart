String formatEgp(int piastres) {
  final pounds = piastres ~/ 100;
  final fraction = (piastres % 100).toString().padLeft(2, '0');
  return '$pounds.$fraction ج.م';
}