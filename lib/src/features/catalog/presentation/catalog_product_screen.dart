import '../../../core/widgets/page_shimmer.dart';
import 'dart:async';
import '../../cloud/application/cloud_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Variable;
import '../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../application/catalog_providers.dart';
import '../domain/catalog_repository.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/money.dart';
import '../../products/data/product_editor_repository.dart';
import '../../products/data/product_unit_settings.dart';
import '../../products/presentation/product_form.dart';
import '../../products/presentation/product_photo.dart';
import '../../products/presentation/variant_sales_list.dart';
import '../../products/presentation/add_to_cashier.dart';
import '../../inventory/presentation/stock_intake_dialog.dart';
import '../../barcode/application/product_barcode_printer.dart';
import '../../shared/presentation/operation_widgets.dart'
    show formatCurrency, showFailure;

String rupiah(int value) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
).format(value);

class CatalogProductScreen extends ConsumerStatefulWidget {
  const CatalogProductScreen({super.key, required this.productId});
  final int productId;
  @override
  ConsumerState<CatalogProductScreen> createState() =>
      _CatalogProductScreenState();
}

class _CatalogProductScreenState extends ConsumerState<CatalogProductScreen> {
  bool busy = false;
  int get productId => widget.productId;

  Future<void> printBarcode(String owner, String name, String code) async {
    if (busy ||
        code.trim().isEmpty ||
        ref.read(authProvider).user?.uid != owner) {
      return;
    }
    setState(() => busy = true);
    try {
      final sent = await ref
          .read(productBarcodePrinterProvider)
          .print(owner, name: name, code: code);
      if (mounted && sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permintaan cetak barcode terkirim')),
        );
      }
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void refresh(String owner) {
    final key = (owner, productId);
    ref.invalidate(catalogDetailProvider(key));
    ref.invalidate(localProductsProvider(owner));
    ref.invalidate(productMetadataProvider(key));
    ref.invalidate(productPhotoProvider(key));
    ref.invalidate(productRetailPricesProvider(owner));
  }

  Future<void> editProduct(String owner) async {
    try {
      final products = await ref
          .read(businessRepositoryProvider)
          .products(owner);
      final product = products.singleWhere((p) => p.id == productId);
      if (!mounted || ref.read(authProvider).user?.uid != owner) return;
      await showProductForm(context, owner, product: product);
      if (mounted) refresh(owner);
    } catch (error) {
      if (mounted) await showFailure(context, error);
    }
  }

  Future<void> archive(String owner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus produk?'),
        content: Text(
          'Produk akan disembunyikan dari katalog dan kasir. Riwayat transaksi tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        ref.read(authProvider).user?.uid != owner) {
      return;
    }
    setState(() => busy = true);
    try {
      await ref.read(productEditorProvider).archive(owner, productId);
      ref.invalidate(localProductsProvider(owner));
      if (mounted) context.go('/products');
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> favorite(String owner, bool value) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(productEditorProvider)
          .setFavorite(owner, productId, value);
      ref.invalidate(productMetadataProvider((owner, productId)));
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> add(String owner) async {
    if (busy) return;
    setState(() => busy = true);
    await addProductToCashier(context, ref, owner, productId);
    if (mounted) setState(() => busy = false);
  }

  Future<void> addStock(String owner, String currency) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final saved = await showStockIntake(
        context,
        ref,
        owner,
        productId,
        currency,
      );
      if (saved && mounted && ref.read(authProvider).user?.uid == owner) {
        refresh(owner);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Stok masuk tersimpan')));
      }
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    final key = (owner, productId);
    final metadata = ref.watch(productMetadataProvider(key)).valueOrNull ?? {};
    final data = ref.watch(catalogDetailProvider(key));
    final currency =
        ref.watch(businessProfileProvider(owner)).valueOrNull?.currency ??
        'IDR';
    final photo = ref.watch(productPhotoProvider(key)).valueOrNull;
    final available =
        metadata['product_type'] == 'service' ||
        (data.valueOrNull?.$3.quantity.compareTo(Rational.zero) ?? 0) > 0;
    final wide =
        MediaQuery.sizeOf(context).width >= 1100 &&
        MediaQuery.textScalerOf(context).scale(14) < 22;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/products');
            }
          },
        ),
        title: Text(
          'Detail Produk',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Hapus produk',
            onPressed: busy ? null : () => archive(owner),
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.danger,
              size: 20,
            ),
          ),
          if (wide)
            FilledButton.icon(
              onPressed: busy ? null : () => editProduct(owner),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text('Edit Produk'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => editProduct(owner),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: busy || !available ? null : () => add(owner),
                        icon: const Icon(
                          Icons.shopping_cart_outlined,
                          size: 18,
                        ),
                        label: Text('Tambah ke Kasir'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: data.when(
          loading: () => const PageShimmer(),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => refresh(owner),
              child: Text('Muat ulang produk'),
            ),
          ),
          data: (data) {
            final (product, prices, balance) = data;
            final baseUnit = product.units[product.baseUnitId]!;
            final baseStock = '${balance.quantity.display} $baseUnit';
            final breakdown = balance.quantity.isNegative
                ? baseStock
                : product.graph
                      .decompose(balance.quantity, product.units.keys)
                      .entries
                      .map(
                        (entry) =>
                            '${entry.value.display} ${product.units[entry.key]}',
                      )
                      .join(' + ');
            final stock = breakdown.isEmpty || breakdown == baseStock
                ? baseStock
                : '$breakdown ($baseStock)';
            final defaultPrices = ref
                .watch(productRetailPricesProvider(owner))
                .valueOrNull?[productId];
            final retail = [
              ...(defaultPrices ??
                  prices
                      .where(
                        (p) =>
                            p.kind == PriceKind.retail &&
                            p.minimum.isZero &&
                            p.customerId == null &&
                            p.variantId == null,
                      )
                      .map((p) => (product.units[p.unitId]!, p.price.rupiah))
                      .toList()),
            ];
            final unitIds = {
              for (final entry in product.units.entries) entry.value: entry.key,
            };
            retail.sort(
              (a, b) => product.graph
                  .factor(unitIds[b.$1]!)
                  .compareTo(product.graph.factor(unitIds[a.$1]!)),
            );
            final orderedPrices = [...prices]
              ..sort(
                (a, b) => product.graph
                    .factor(b.unitId)
                    .compareTo(product.graph.factor(a.unitId)),
              );
            Future<void> editUnit([UnitPrice? existing]) async {
              await showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => _UnitPriceDialog(
                  owner: owner,
                  product: product,
                  existing: existing,
                ),
              );
              if (mounted) refresh(owner);
            }

            Widget photoPane() => AspectRatio(
              aspectRatio: 1,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ProductPhoto(
                        bytes: photo,
                        size: null,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: IconButton.filledTonal(
                        tooltip: 'Ubah gambar',
                        onPressed: busy ? null : () => editProduct(owner),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            );

            Widget information() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: metadata['favorite'] == '1'
                          ? 'Hapus dari favorit'
                          : 'Tambahkan ke favorit',
                      onPressed: busy
                          ? null
                          : () => favorite(owner, metadata['favorite'] != '1'),
                      icon: Icon(
                        metadata['favorite'] == '1'
                            ? Icons.star
                            : Icons.star_border,
                        color: AppColors.electricBlue,
                      ),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _DetailBadge('Aktif', true),
                ),
                const SizedBox(height: 8),
                Text(
                  [metadata['brand'], metadata['category']]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(' - '),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                _detailTitle('Informasi Harga'),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, size) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: retail
                        .map(
                          (price) => SizedBox(
                            width: (size.maxWidth - 8) / 2,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      formatCurrency(price.$2, currency),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'per ${price.$1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 22),
                _detailTitle('Stok'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(stock, style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 6),
                      _DetailBadge(available ? 'Tersedia' : 'Habis', available),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _detailTitle('Deskripsi'),
                const SizedBox(height: 10),
                Text(
                  metadata['description']?.isNotEmpty == true
                      ? metadata['description']!
                      : '-',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 22),
                _detailTitle('Informasi Lainnya'),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      _infoRow(
                        'Barcode',
                        metadata['barcode'] ?? '',
                        copy: true,
                      ),
                      _infoRow('Kategori', metadata['category'] ?? ''),
                      _infoRow('Merek', metadata['brand'] ?? ''),
                      _infoRow('SKU', metadata['sku'] ?? ''),
                      _infoRow('Dibuat', _date(metadata['created_at'])),
                      _infoRow('Diubah', _date(metadata['updated_at'])),
                    ],
                  ),
                ),
              ],
            );

            Widget settings() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detailTitle('Stok & Konversi'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stok Total',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        baseStock,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        breakdown.isEmpty ? '-' : breakdown,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Stok Minimum: ${metadata['minimum'] ?? '0'} $baseUnit',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (metadata['product_type'] != 'service') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('product-add-stock'),
                    onPressed: busy ? null : () => addStock(owner, currency),
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: Text('Tambah Stok'),
                  ),
                ],
                ProductVariantSales(owner: owner, productId: widget.productId),
                const SizedBox(height: 22),
                _detailTitle('Satuan Penjualan'),
                const SizedBox(height: 10),
                ...orderedPrices.map(
                  (price) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Edit satuan dan harga',
                          onPressed: busy ? null : () => editUnit(price),
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppColors.electricBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.units[price.unitId]!,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '1 ${product.units[price.unitId]} = ${product.graph.factor(price.unitId).display} $baseUnit',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                'Minimum ${price.minimum.display}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              formatCurrency(price.price.rupiah, currency),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => editUnit(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Tambah satuan / harga'),
                ),
                const SizedBox(height: 22),
                _detailTitle('Harga Beli Rata-Rata'),
                const SizedBox(height: 10),
                if (!balance.costKnown)
                  Text(
                    '-',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ...retail.map(
                    (price) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'per ${price.$1}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            formatCurrency(
                              Money.fromBigInt(
                                (balance.averageCost *
                                        product.graph.factor(
                                          unitIds[price.$1]!,
                                        ))
                                    .roundHalfUp(),
                              ).rupiah,
                              currency,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Izinkan stok negatif',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: product.allowNegative,
                  onChanged: busy
                      ? null
                      : (value) async {
                          try {
                            await ref
                                .read(catalogRepositoryProvider)
                                .setAllowNegative(owner, productId, value);
                            if (mounted) refresh(owner);
                          } catch (error) {
                            if (context.mounted) {
                              await showFailure(context, error);
                            }
                          }
                        },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('product-print-barcode'),
                  onPressed: busy || (metadata['barcode'] ?? '').trim().isEmpty
                      ? null
                      : () => printBarcode(
                          owner,
                          product.name,
                          metadata['barcode']!,
                        ),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Cetak Barcode'),
                ),
                const SizedBox(height: 12),
              ],
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 200,
                        child: Column(
                          children: [
                            photoPane(),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: busy || !available
                                    ? null
                                    : () => add(owner),
                                icon: const Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 18,
                                ),
                                label: Text('Tambah ke Kasir'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(flex: 4, child: information()),
                      const SizedBox(width: 24),
                      Expanded(flex: 5, child: settings()),
                    ],
                  )
                else ...[
                  photoPane(),
                  const SizedBox(height: 12),
                  information(),
                  const SizedBox(height: 24),
                  settings(),
                ],
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _detailTitle(String value) => Text(
    value,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
  String _date(String? value) {
    final timestamp = int.tryParse(value ?? '');
    return timestamp == null
        ? '-'
        : DateFormat(
            'dd MMM yyyy, HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(timestamp));
  }

  Widget _infoRow(String label, String value, {bool copy = false}) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (copy && value.isNotEmpty)
                IconButton(
                  tooltip: 'Salin barcode',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Barcode disalin')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined, size: 14),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Text(
            value.isEmpty ? '-' : value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge(this.label, this.positive);
  final String label;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: positive
          ? AppStatusColors.of(context).success.withValues(alpha: .12)
          : Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: positive
            ? AppStatusColors.of(context).success
            : Theme.of(context).colorScheme.onErrorContainer,
      ),
    ),
  );
}

class _UnitPriceDialog extends ConsumerStatefulWidget {
  const _UnitPriceDialog({
    required this.owner,
    required this.product,
    this.existing,
  });
  final String owner;
  final CatalogProduct product;
  final UnitPrice? existing;
  @override
  ConsumerState<_UnitPriceDialog> createState() => _UnitPriceDialogState();
}

class _UnitPriceDialogState extends ConsumerState<_UnitPriceDialog> {
  final form = GlobalKey<FormState>();
  final unit = TextEditingController(),
      ratio = TextEditingController(text: '1'),
      price = TextEditingController(),
      buyPrice = TextEditingController();
  bool cashierActive = true, saving = false, metadataLoaded = true;
  String? error;
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      unit.text = widget.product.units[existing.unitId]!;
      ratio.text = widget.product.graph.factor(existing.unitId).display;
      price.text = '${existing.price.rupiah}';
      metadataLoaded = false;
      loadUnitSettings(existing.unitId);
    }
  }

  @override
  void dispose() {
    for (final c in [unit, ratio, price, buyPrice]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> loadUnitSettings(int unitId) async {
    try {
      final rows = await ref
          .read(databaseProvider)
          .customSelect(
            'SELECT name,value FROM product_attributes WHERE owner_id=? AND product_id=? AND variant_id IS NULL AND name IN (?,?)',
            variables: [
              Variable(widget.owner),
              Variable(widget.product.id),
              Variable('cashier_unit_$unitId'),
              Variable('buy_price_unit_$unitId'),
            ],
          )
          .get();
      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          if (row.read<String>('name') == 'cashier_unit_$unitId') {
            cashierActive = row.read<String>('value') != '0';
          } else {
            buyPrice.text = row.read<String>('value');
          }
        }
        metadataLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Pengaturan satuan belum dapat dibuka. Tutup lalu coba lagi.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(
      TextEditingController controller,
      String label, {
      bool quantity = false,
      bool money = false,
      bool optional = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !saving,
        decoration: InputDecoration(labelText: label),
        keyboardType: quantity || money
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        validator: (v) {
          if (v == null || v.trim().isEmpty) {
            return optional ? null : '$label wajib diisi';
          }
          if (money) {
            final n = int.tryParse(v);
            if (n == null || n < 0 || n > maxExactInteger) {
              return 'Masukkan Rupiah bulat';
            }
          }
          if (quantity) {
            try {
              final q = Rational.parse(v);
              fractionRangeCheck(q);
              if (q.isNegative || (controller == ratio && q.isZero)) {
                return 'Jumlah tidak valid';
              }
            } catch (_) {
              return 'Masukkan desimal atau pecahan yang valid';
            }
          }
          return null;
        },
      ),
    );

    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text('Satuan dan harga'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field(unit, 'Satuan penjualan'),
                  field(
                    ratio,
                    'Isi dalam ${widget.product.units[widget.product.baseUnitId]}',
                    quantity: true,
                  ),
                  field(
                    price,
                    cashierActive ? 'Harga jual *' : 'Harga jual (opsional)',
                    money: true,
                    optional: !cashierActive,
                  ),
                  field(
                    buyPrice,
                    cashierActive ? 'Harga beli (opsional)' : 'Harga beli *',
                    money: true,
                    optional: cashierActive,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Tampilkan di kasir'),
                    value: cashierActive,
                    onChanged: saving || !metadataLoaded
                        ? null
                        : (value) => setState(() => cashierActive = value!),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (saving) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: Text('Batal'),
          ),
          FilledButton(
            onPressed: saving || !metadataLoaded
                ? null
                : () async {
                    if (saving || !(form.currentState?.validate() ?? false)) {
                      return;
                    }
                    if (ref.read(authProvider).user?.uid != widget.owner) {
                      return;
                    }
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final db = ref.read(databaseProvider);
                      final catalog = ref.read(catalogRepositoryProvider);
                      await db.transaction(() async {
                        final list = await db
                            .customSelect(
                              'SELECT name FROM price_lists WHERE owner_id=? AND is_default=1',
                              variables: [Variable(widget.owner)],
                            )
                            .getSingle();
                        await catalog.configureUnitPrice(
                          widget.owner,
                          widget.product.id,
                          unitName: unit.text,
                          toBase: Rational.parse(ratio.text),
                          listName: list.read<String>('name'),
                          kind: PriceKind.retail,
                          price: Money(
                            price.text.trim().isEmpty && !cashierActive
                                ? 0
                                : int.parse(price.text.trim()),
                          ),
                          minimum: Rational.zero,
                          variantId: widget.existing?.variantId,
                          previousPriceId: widget.existing?.id,
                        );
                        final updated = await catalog.product(
                          widget.owner,
                          widget.product.id,
                        );
                        final unitId = updated.units.entries
                            .firstWhere(
                              (entry) =>
                                  entry.value.toLowerCase() ==
                                  unit.text.trim().toLowerCase(),
                            )
                            .key;
                        await ProductUnitSettings(db).save(
                          widget.owner,
                          widget.product.id,
                          unitId,
                          cashierActive: cashierActive,
                          buyPrice: buyPrice.text.trim().isEmpty
                              ? null
                              : int.parse(buyPrice.text.trim()),
                        );
                      });
                      unawaited(
                        ref
                            .read(cloudSyncProvider)
                            .syncAfterChange(widget.owner),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          error = e is StateError
                              ? e.message.toString()
                              : e is ArgumentError
                              ? 'Periksa satuan, rasio, harga dan tanggal.'
                              : 'Pengaturan belum tersimpan. Coba lagi.';
                        });
                      }
                    }
                  },
            child: Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
