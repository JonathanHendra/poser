String formatSaleNumber(int index, DateTime date) {
  if (index < 1 || index > 999999) {
    throw const FormatException('Batas nomor penjualan tahunan terlampaui.');
  }
  return '${index.toString().padLeft(6, '0')}${date.month.toString().padLeft(2, '0')}${(date.year % 100).toString().padLeft(2, '0')}';
}
