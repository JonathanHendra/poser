import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/page_shimmer.dart';
import '../data/variant_sales_repository.dart';

class VariantSalesList extends StatelessWidget {
  const VariantSalesList({super.key, required this.entries});
  final List<VariantSales> entries;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, entry) in entries.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  entry.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${entry.quantity.display} ${entry.unit}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class ProductVariantSales extends ConsumerWidget {
  const ProductVariantSales({
    super.key,
    required this.owner,
    required this.productId,
  });
  final String owner;
  final int productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(productVariantSalesProvider((owner, productId)))
      .when(
        loading: () =>
            const SizedBox(height: 100, child: ClipRect(child: PageShimmer())),
        error: (_, _) => TextButton.icon(
          onPressed: () =>
              ref.invalidate(productVariantSalesProvider((owner, productId))),
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang varian terlaris'),
        ),
        data: (entries) => entries.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Varian Terlaris',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Semua Waktu',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    VariantSalesList(entries: entries),
                  ],
                ),
              ),
      );
}
