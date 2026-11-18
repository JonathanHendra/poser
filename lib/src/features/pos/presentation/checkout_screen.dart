import '../../../core/widgets/page_shimmer.dart';
import 'dart:async';
import '../../cloud/application/cloud_sync.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import '../../../core/theme/brand_logo.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/rational.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../barcode/presentation/scanner.dart';
import '../../products/presentation/product_photo.dart';
import '../../shared/presentation/product_picker.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../../sales/domain/sale_models.dart';
import '../../payments/presentation/payment_dialog.dart';
import '../application/pos_controller.dart';
import '../application/cashier_catalog.dart';

final posOptionsProvider = FutureProvider.autoDispose
    .family<Map<String, List<(int, String)>>, String>((ref, owner) async {
      final db = ref.watch(databaseProvider);
      final result = <String, List<(int, String)>>{};
      for (final table in ['stores', 'customers', 'packages']) {
        final rows = await db
            .customSelect(
              'SELECT id,name FROM $table WHERE owner_id = ? ${['stores', 'packages'].contains(table) ? 'AND active = 1' : ''} ORDER BY name',
              variables: [Variable(owner)],
            )
            .get();
        result[table] = rows
            .map((r) => (r.read<int>('id'), r.read<String>('name')))
            .toList();
      }
      return result;
    });

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, this.showCart = false});
  final bool showCart;
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final search = TextEditingController();
  final cartTarget = GlobalKey();
  final productKeys = <int, GlobalKey>{};
  final flyingProducts = <OverlayEntry>{};
  String query = '';
  String? category;
  bool cartTab = false, selecting = false, paying = false;
  bool removingItem = false;
  String currency = 'IDR';
  String price(int value) => formatCurrency(value, currency);
  IconData _categoryIcon(String? name) {
    final value = name?.toLowerCase() ?? '';
    if (value.contains('makan')) return Icons.lunch_dining_outlined;
    if (value.contains('minum')) return Icons.local_drink_outlined;
    if (value.contains('rokok')) return Icons.smoking_rooms_outlined;
    if (value.contains('sembako')) return Icons.shopping_basket_outlined;
    if (value.contains('rumah')) return Icons.home_work_outlined;
    if (name == null) return Icons.shopping_bag_outlined;
    return Icons.inventory_2_outlined;
  }

  void removeLine(PosController cart, int index) {
    cart.remove(index);
    if (cart.items.isEmpty) setState(() => cartTab = false);
  }

  Future<void> changeQuantity(PosController cart, int index, int delta) async {
    if (cart.busy || selecting) return;
    final line = cart.items[index];
    final quantity = line.quantity + Rational.of(delta);
    if (quantity.isNegative || quantity.isZero) {
      removeLine(cart, index);
      return;
    }
    final updated = SaleLineRequest(
      productId: line.productId,
      unitId: line.unitId,
      variantId: line.variantId,
      variantQuantities: {
        for (final entry in line.variantQuantities.entries)
          entry.key: entry.value * quantity / line.quantity,
      },
      variantInputUnitId: line.variantInputUnitId,
      quantity: quantity,
      packageId: line.packageId,
      modifierIds: line.modifierIds,
      discount: line.discount,
    );
    if (line.variantQuantities.isNotEmpty) {
      setState(() => selecting = true);
      try {
        final picked = await configureLine(
          context,
          ref,
          cart.owner,
          line.productId,
          initial: updated,
          priceListId: cart.priceListId,
          customerId: cart.customerId,
        );
        if (picked != null &&
            mounted &&
            ref.read(authProvider).user?.uid == cart.owner &&
            index < cart.items.length &&
            identical(cart.items[index], line)) {
          cart.replaceAll(index, picked.lines);
        }
      } catch (error) {
        if (mounted) await showFailure(context, error);
      } finally {
        if (mounted) setState(() => selecting = false);
      }
    } else {
      cart.replace(index, updated);
    }
  }

  @override
  void dispose() {
    for (final entry in flyingProducts) {
      entry.remove();
      entry.dispose();
    }
    search.dispose();
    super.dispose();
  }

  Future<void> add(
    String owner,
    int productId, {
    int? unitId,
    int? variantId,
  }) async {
    if (selecting || ref.read(posControllerProvider(owner)).busy) return;
    selecting = true;
    try {
      final products = await ref.read(
        cashierCatalogProvider((
          owner,
          ref.read(posControllerProvider(owner)).storeId,
        )).future,
      );
      if (!mounted || ref.read(authProvider).user?.uid != owner) return;
      final item = products.firstWhere((item) => item.product.id == productId);
      if (!item.available) return;
      final selection = await configureLine(
        context,
        ref,
        owner,
        productId,
        unitId: unitId ?? item.sellingUnitId,
        variantId: variantId,
        priceListId: ref.read(posControllerProvider(owner)).priceListId,
        customerId: ref.read(posControllerProvider(owner)).customerId,
      );
      if (selection != null &&
          mounted &&
          ref.read(authProvider).user?.uid == owner) {
        ref.read(posControllerProvider(owner)).addAll(selection.lines);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) animateProduct(productId);
        });
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      selecting = false;
    }
  }

  void animateProduct(int id) {
    if (MediaQuery.of(context).disableAnimations) return;
    final source = productKeys[id]?.currentContext?.findRenderObject();
    final target = cartTarget.currentContext?.findRenderObject();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject();
    if (source is! RenderBox ||
        target is! RenderBox ||
        overlayBox is! RenderBox) {
      return;
    }
    final from = overlayBox.globalToLocal(
      source.localToGlobal(source.size.center(Offset.zero)),
    );
    final to = overlayBox.globalToLocal(
      target.localToGlobal(target.size.center(Offset.zero)),
    );
    final owner = ref.read(authProvider).user?.uid;
    if (owner == null) return;
    final photo = ref
        .read(localProductsProvider(owner))
        .valueOrNull
        ?.where((p) => p.id == id)
        .firstOrNull
        ?.photo;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
        onEnd: () {
          if (flyingProducts.remove(entry)) {
            entry.remove();
            entry.dispose();
          }
        },
        builder: (context, progress, child) {
          final position =
              Offset.lerp(from, to, progress)! -
              Offset(0, 70 * 4 * progress * (1 - progress));
          final size = 56 - 32 * progress;
          return Positioned(
            left: position.dx - size / 2,
            top: position.dy - size / 2,
            width: size,
            height: size,
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - progress * .6,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: ProductPhoto(
                    bytes: photo,
                    size: size,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    flyingProducts.add(entry);
    overlay.insert(entry);
  }

  Future<void> barcode(String owner, String code) async {
    try {
      final match = await resolveBarcode(context, ref, owner, code);
      if (match != null && mounted) {
        await add(
          owner,
          match.productId,
          unitId: match.unitId,
          variantId: match.variantId,
        );
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  Future<void> resume(String owner) async {
    try {
      final rows = await ref.read(cartRepositoryProvider).list(owner);
      if (!mounted) return;
      final id = await showDialog<int>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Keranjang tersimpan'),
          content: SizedBox(
            width: 420,
            child: rows.isEmpty
                ? const Text('Belum ada keranjang tersimpan')
                : ListView(
                    shrinkWrap: true,
                    children: rows
                        .map(
                          (row) => ListTile(
                            title: Text(row.read<String>('name')),
                            onTap: () => Navigator.pop(c, row.read<int>('id')),
                            trailing: IconButton(
                              tooltip: 'Hapus keranjang',
                              onPressed: () async {
                                await ref
                                    .read(cartRepositoryProvider)
                                    .discard(owner, row.read<int>('id'));
                                if (c.mounted) Navigator.pop(c);
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
      if (id != null && mounted && ref.read(authProvider).user?.uid == owner) {
        await ref.read(posControllerProvider(owner)).resume(id);
        if (mounted) setState(() => cartTab = true);
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  Future<void> hold(String owner) async {
    final name = await askText(context, 'Nama keranjang');
    if (name == null || !mounted || ref.read(authProvider).user?.uid != owner) {
      return;
    }
    try {
      await ref.read(posControllerProvider(owner)).hold(name);
      if (mounted) setState(() => cartTab = false);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  Future<void> discounts(String owner, PosController cart) async {
    var percentage = cart.discountBasisPoints != 0;
    final amount = TextEditingController(
      text: percentage
          ? Rational.of(cart.discountBasisPoints, 100).display
          : '${cart.discount.rupiah}',
    );
    final tax = TextEditingController(
      text: Rational.of(cart.taxBasisPoints, 100).display,
    );
    String? error;
    await showOperationDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Diskon dan pajak'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Rupiah')),
                    ButtonSegment(value: true, label: Text('Persen')),
                  ],
                  selected: {percentage},
                  onSelectionChanged: (v) => set(() {
                    percentage = v.single;
                    amount.text = '0';
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Diskon transaksi',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tax,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Pajak (%)'),
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  int rate(String value) {
                    final rational =
                        Rational.parse(value.replaceAll(',', '.')) *
                        Rational.of(100);
                    if (rational.denominator != BigInt.one ||
                        rational.isNegative ||
                        rational.compareTo(Rational.of(10000)) > 0) {
                      throw const FormatException();
                    }
                    return checkedInteger(rational.numerator);
                  }

                  final bps = percentage ? rate(amount.text) : 0,
                      fixed = percentage
                          ? Money(0)
                          : Money(int.parse(amount.text)),
                      taxBps = rate(tax.text);
                  SaleTotals.calculate(
                    subtotal: cart.quoted.fold<Money>(
                      Money(0),
                      (s, l) => s + l.subtotal - (l.itemDiscount ?? Money(0)),
                    ),
                    fixedDiscount: percentage ? null : fixed,
                    discountBasisPoints: bps,
                    taxBasisPoints: taxBps,
                  );
                  if (ref.read(authProvider).user?.uid != owner) return;
                  cart.discount = fixed;
                  cart.discountBasisPoints = bps;
                  cart.taxBasisPoints = taxBps;
                  cart.changed();
                  Navigator.pop(c);
                } catch (_) {
                  set(
                    () => error =
                        'Diskon/pajak tidak valid. Persen maksimal 100 dengan 2 desimal.',
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    tax.dispose();
  }

  Future<void> checkout(String owner, PosController cart) async {
    if (paying || cart.busy) return;
    setState(() => paying = true);
    try {
      await cart.refresh();
      if (!mounted ||
          cart.error != null ||
          ref.read(authProvider).user?.uid != owner) {
        if (cart.error != null && mounted) {
          await showFailure(context, cart.error!);
        }
        return;
      }
      final payments = await collectPayments(
        context,
        cart.due,
        currency: currency,
      );
      if (payments == null ||
          !mounted ||
          ref.read(authProvider).user?.uid != owner) {
        return;
      }
      final sale = await cart.checkout(payments);
      unawaited(ref.read(cloudSyncProvider).syncAfterChange(owner));
      if (mounted) setState(() => cartTab = false);
      ref.invalidate(localProductsProvider(owner));
      if (mounted && ref.read(authProvider).user?.uid == owner) {
        context.go('/cashier/success/${sale.id}');
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  Widget catalog(
    String owner,
    Map<String, List<(int, String)>> options,
  ) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: TextField(
          key: const ValueKey('pos-search'),
          controller: search,
          onChanged: (v) => setState(() => query = v.toLowerCase().trim()),
          onSubmitted: (v) => barcode(owner, v),
          decoration: InputDecoration(
            hintText: 'Cari produk / scan barcode',
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkFieldBorder
                    : AppColors.navy,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkFieldFocusedBorder
                    : AppColors.navy,
                width: 1.5,
              ),
            ),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Padding(
              padding: const EdgeInsets.all(6),
              child: IconButton(
                tooltip: 'Scan barcode',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.electricBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(42, 42),
                ),
                onPressed: () async {
                  final code = await scanBarcode(context);
                  if (code != null && mounted) await barcode(owner, code);
                },
                icon: const Icon(Icons.qr_code_scanner, size: 22),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: ref
            .watch(
              cashierCatalogProvider((
                owner,
                ref.watch(posControllerProvider(owner)).storeId,
              )),
            )
            .when(
              loading: () => const PageShimmer(),
              error: (e, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(
                    cashierCatalogProvider((
                      owner,
                      ref.read(posControllerProvider(owner)).storeId,
                    )),
                  ),
                  child: const Text('Coba lagi'),
                ),
              ),
              data: (entries) {
                final items = entries.map((entry) => entry.product).toList();
                final availability = {
                  for (final entry in entries) entry.product.id: entry,
                };
                final products = items
                    .where(
                      (p) =>
                          (category == null || p.category == category) &&
                          (p.name.toLowerCase().contains(query) ||
                              (p.barcode ?? '').contains(query) ||
                              (p.sku ?? '').toLowerCase().contains(query)),
                    )
                    .toList();
                final packages = (options['packages'] ?? [])
                    .where((p) => p.$2.toLowerCase().contains(query))
                    .toList();
                if (items.isEmpty && packages.isEmpty) {
                  return const Center(child: Text('Produk tidak ditemukan'));
                }
                return LayoutBuilder(
                  builder: (gridContext, size) => CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height:
                              56 +
                              (MediaQuery.textScalerOf(context).scale(12) - 12)
                                      .clamp(0, double.infinity) *
                                  2,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children:
                                [
                                      null,
                                      ...(items
                                          .map((p) => p.category)
                                          .whereType<String>()
                                          .toSet()
                                          .toList()
                                        ..sort()),
                                    ]
                                    .map(
                                      (name) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                          bottom: 8,
                                        ),
                                        child: ChoiceChip(
                                          avatar: Icon(
                                            _categoryIcon(name),
                                            size: 16,
                                            color: category == name
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onPrimary
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                          label: Text(name ?? 'Semua'),
                                          labelStyle: TextStyle(
                                            color: category == name
                                                ? Colors.white
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          selectedColor: AppColors.electricBlue,
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerLow,
                                          selected: category == name,
                                          onSelected: (_) =>
                                              setState(() => category = name),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    (size.maxWidth /
                                            (MediaQuery.textScalerOf(
                                                      context,
                                                    ).scale(14) >
                                                    22
                                                ? 220
                                                : 138))
                                        .floor()
                                        .clamp(
                                          size.maxWidth < 340 &&
                                                  MediaQuery.textScalerOf(
                                                        context,
                                                      ).scale(14) >
                                                      22
                                              ? 1
                                              : 2,
                                          6,
                                        ),
                                mainAxisExtent:
                                    222 +
                                    (MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(14) -
                                                14)
                                            .clamp(0, double.infinity) *
                                        5,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final p = products[index];
                            final available = availability[p.id]!.available;
                            return Material(
                              key: productKeys.putIfAbsent(
                                p.id!,
                                () => GlobalKey(),
                              ),
                              color: available
                                  ? Theme.of(context).colorScheme.surface
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(
                                        alpha:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? .32
                                            : .45,
                                      ),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: available
                                    ? () => add(owner, p.id!)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surfaceContainerLow,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: ProductPhoto(
                                            bytes: p.photo,
                                            size: null,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        p.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${price(availability[p.id]!.sellingPrice)} / ${availability[p.id]!.sellingUnit}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.productType == 'service'
                                                  ? 'Jasa'
                                                  : available
                                                  ? 'Stok: ${availability[p.id]!.stockDescription}'
                                                  : 'Stok habis',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Tambahkan ${p.name}',
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 30,
                                                  height: 30,
                                                ),
                                            padding: EdgeInsets.zero,
                                            iconSize: 18,
                                            style: IconButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.electricBlue,
                                              foregroundColor: Colors.white,
                                              disabledBackgroundColor:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                              disabledForegroundColor: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            onPressed: available
                                                ? () => add(owner, p.id!)
                                                : null,
                                            icon: const Icon(Icons.add),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SliverList.list(
                        children: [
                          ...packages.map(
                            (package) => ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(package.$2),
                              subtitle: const Text('Paket'),
                              onTap: () async {
                                try {
                                  final rows = await ref
                                      .read(databaseProvider)
                                      .customSelect(
                                        'SELECT i.*,p.base_unit_id FROM package_items i JOIN products p ON p.owner_id = i.owner_id AND p.id = i.product_id WHERE i.owner_id = ? AND i.package_id = ? ORDER BY i.id',
                                        variables: [
                                          Variable(owner),
                                          Variable(package.$1),
                                        ],
                                      )
                                      .get();
                                  if (rows.isEmpty) {
                                    throw StateError('Paket kosong');
                                  }
                                  if (!mounted) return;
                                  final quantity = await askText(
                                    context,
                                    'Jumlah paket',
                                    initial: '1',
                                    numeric: true,
                                  );
                                  if (quantity != null &&
                                      mounted &&
                                      ref.read(authProvider).user?.uid ==
                                          owner) {
                                    ref
                                        .read(posControllerProvider(owner))
                                        .add(
                                          SaleLineRequest(
                                            productId: rows.first.read<int>(
                                              'product_id',
                                            ),
                                            unitId: rows.first.read<int>(
                                              'base_unit_id',
                                            ),
                                            quantity: Rational.parse(quantity),
                                            packageId: package.$1,
                                          ),
                                        );
                                  }
                                } catch (e) {
                                  if (mounted) await showFailure(context, e);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    ],
  );
  Widget basket(
    String owner,
    PosController cart,
    Map<String, List<(int, String)>> options,
  ) {
    return Column(
      children: [
        if (cart.quoting) const LinearProgressIndicator(),
        Expanded(
          child: cart.items.isEmpty
              ? const Center(child: Text('Keranjang kosong'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: cart.items.length,
                  itemBuilder: (c, i) {
                    final request = cart.items[i];
                    final line = i < cart.quoted.length ? cart.quoted[i] : null;
                    return Dismissible(
                      key: ObjectKey(request),
                      direction: cart.busy || cart.quoting
                          ? DismissDirection.none
                          : DismissDirection.endToStart,
                      background: ColoredBox(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Icon(
                              Icons.delete_outline,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                      confirmDismiss: (_) async {
                        if (cart.busy ||
                            cart.quoting ||
                            removingItem ||
                            ref.read(authProvider).user?.uid != owner) {
                          return false;
                        }
                        setState(() => removingItem = true);
                        return true;
                      },
                      onDismissed: (_) {
                        final index = cart.items.indexWhere(
                          (item) => identical(item, request),
                        );
                        if (index >= 0) removeLine(cart, index);
                        setState(() => removingItem = false);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? AppColors.electricBlue
                                          : Colors.black)
                                      .withValues(alpha: .12),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap:
                              cart.busy ||
                                  removingItem ||
                                  cart.items[i].packageId != null
                              ? null
                              : () async {
                                  try {
                                    final picked = await configureLine(
                                      context,
                                      ref,
                                      owner,
                                      cart.items[i].productId,
                                      initial: cart.items[i],
                                    );
                                    if (picked != null &&
                                        mounted &&
                                        ref.read(authProvider).user?.uid ==
                                            owner) {
                                      cart.replaceAll(i, picked.lines);
                                    }
                                  } catch (e) {
                                    if (mounted) await showFailure(context, e);
                                  }
                                },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ProductPhoto(
                                  bytes: ref
                                      .watch(localProductsProvider(owner))
                                      .valueOrNull
                                      ?.where(
                                        (p) => p.id == cart.items[i].productId,
                                      )
                                      .firstOrNull
                                      ?.photo,
                                  size: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line?.productName ??
                                          'Produk #${cart.items[i].productId}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (line != null &&
                                        line.modifiers.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        line.modifiers
                                            .map((m) => '${m['name']}')
                                            .join(', '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                    if (line != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        price(
                                          (line.subtotal -
                                                  (line.itemDiscount ??
                                                      Money(0)))
                                              .rupiah,
                                        ),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        _QuantityButton(
                                          tooltip: 'Kurangi jumlah',
                                          icon: Icons.remove,
                                          onPressed:
                                              cart.busy ||
                                                  cart.quoting ||
                                                  removingItem
                                              ? null
                                              : () =>
                                                    changeQuantity(cart, i, -1),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            (line?.saleQuantity ??
                                                    cart.items[i].quantity)
                                                .display,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        _QuantityButton(
                                          tooltip: 'Tambah jumlah',
                                          icon: Icons.add,
                                          onPressed:
                                              cart.busy ||
                                                  cart.quoting ||
                                                  removingItem
                                              ? null
                                              : () =>
                                                    changeQuantity(cart, i, 1),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (cart.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${cart.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color:
                    (Theme.of(context).brightness == Brightness.dark
                            ? AppColors.electricBlue
                            : Colors.black)
                        .withValues(alpha: .14),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cart.error == null && cart.quoted.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey((owner, cart.heldCartId)),
                        initialValue:
                            cart.customerName ??
                            options['customers']
                                ?.where((entry) => entry.$1 == cart.customerId)
                                .firstOrNull
                                ?.$2 ??
                            '',
                        enabled: !cart.busy && !removingItem && !paying,
                        decoration: const InputDecoration(
                          labelText: 'Pelanggan',
                          hintText: 'Nama pelanggan (opsional)',
                        ),
                        onChanged: cart.setCustomerName,
                      ),
                    ),
                  ],
                ),
                ...[
                  ('Subtotal', cart.totals.subtotal.rupiah),
                  ('Diskon', -cart.totals.discount.rupiah),
                  ('Pajak', cart.totals.tax.rupiah),
                ].map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(entry.$1)),
                        Text(price(entry.$2)),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            price(cart.totals.total.rupiah),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (cart.exchangeSaleId != null)
                  Text(
                    'Retur #${cart.exchangeSaleId}: ${price(cart.exchangeCredit.rupiah)}',
                  ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 52,
                    child: IconButton.filledTonal(
                      tooltip: 'Diskon dan pajak',
                      onPressed:
                          cart.busy || removingItem || cart.quoted.isEmpty
                          ? null
                          : () => discounts(owner, cart),
                      icon: const Icon(Icons.percent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('pos-pay'),
                      onPressed:
                          paying ||
                              removingItem ||
                              cart.busy ||
                              cart.quoting ||
                              cart.items.isEmpty ||
                              cart.error != null
                          ? null
                          : () => checkout(owner, cart),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(cart.busy ? 'Menyimpan...' : 'Pembayaran'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget compactBasket(String owner, PosController cart, double height) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: (dark ? AppColors.electricBlue : Colors.black).withValues(
              alpha: dark ? .24 : .14,
            ),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _CartBadge(count: cart.items.length),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        cart.error == null
                            ? price(cart.totals.total.rupiah)
                            : 'Periksa keranjang',
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${cart.items.length} item',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  key: cartTarget,
                  width: MediaQuery.sizeOf(context).width < 360 ? 140 : 176,
                  height: 52,
                  child: FilledButton.icon(
                    key: const ValueKey('pos-pay'),
                    onPressed:
                        paying ||
                            removingItem ||
                            cart.busy ||
                            cart.quoting ||
                            cart.error != null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PosScreen(showCart: true),
                            ),
                          ),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text('Keranjang')),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    currency =
        ref.watch(businessProfileProvider(owner)).valueOrNull?.currency ??
        'IDR';
    final cart = ref.watch(posControllerProvider(owner));
    final options = ref.watch(posOptionsProvider(owner));
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: widget.showCart
            ? BackButton(onPressed: () => Navigator.of(context).pop())
            : null,
        title: widget.showCart
            ? const Text(
                'Keranjang',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              )
            : BrandLogo(
                width: MediaQuery.sizeOf(context).width < 360 ? 112 : 142,
              ),
        actions: [
          if (!widget.showCart)
            _HeaderCartButton(
              count: cart.items.length,
              onPressed: cart.items.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PosScreen(showCart: true),
                      ),
                    ),
            ),
          if (!widget.showCart)
            IconButton(
              tooltip: 'Beranda',
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.home_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: options.when(
          loading: () => const PageShimmer(),
          error: (e, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(posOptionsProvider(owner)),
              child: const Text('Coba lagi'),
            ),
          ),
          data: (data) => LayoutBuilder(
            builder: (context, constraints) {
              if (widget.showCart) return basket(owner, cart, data);
              if (constraints.maxWidth >= 600) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: catalog(owner, data)),
                    if (cart.items.isNotEmpty) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: constraints.maxWidth >= 1100 ? 380 : 320,
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                          child: Column(
                            children: [
                              const Spacer(),
                              compactBasket(owner, cart, constraints.maxHeight),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: catalog(owner, data)),
                  if (cart.items.isNotEmpty)
                    compactBasket(owner, cart, constraints.maxHeight),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    iconSize: 18,
    icon: Icon(icon),
  );
}

class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 54,
    height: 54,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            right: -4,
            top: -5,
            child: CircleAvatar(
              radius: 11,
              backgroundColor: AppColors.electricBlue,
              foregroundColor: Colors.white,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _HeaderCartButton extends StatelessWidget {
  const _HeaderCartButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Keranjang',
          onPressed: onPressed,
          icon: const Icon(Icons.shopping_cart_outlined),
        ),
        if (count > 0)
          Positioned(
            right: 1,
            top: 2,
            child: CircleAvatar(
              radius: 9,
              backgroundColor: AppColors.electricBlue,
              foregroundColor: Colors.white,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
