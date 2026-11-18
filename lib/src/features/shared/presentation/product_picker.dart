import '../../../core/widgets/page_shimmer.dart';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Variable, QueryRow;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/domain/rational.dart';
import '../../../core/domain/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../business/application/business_providers.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../barcode/presentation/scanner.dart';
import '../../products/presentation/product_photo.dart';
import '../../products/data/product_editor_repository.dart';
import '../../products/data/product_unit_settings.dart';
import '../../sales/domain/sale_models.dart';
import 'operation_widgets.dart';

class PickedProduct {
  const PickedProduct(
    this.line,
    this.name,
    this.unitCost, {
    this.additionalLines = const [],
  });
  final SaleLineRequest line;
  final List<SaleLineRequest> additionalLines;
  List<SaleLineRequest> get lines => [line, ...additionalLines];
  final String name;
  final Money unitCost;
}

Future<PickedProduct?> pickProduct(
  BuildContext context,
  String owner, {
  bool purchase = false,
  bool inventory = false,
  bool allowZero = false,
}) => Navigator.of(context).push<PickedProduct>(
  MaterialPageRoute(
    builder: (_) => ProductPicker(
      owner: owner,
      purchase: purchase,
      inventory: inventory,
      allowZero: allowZero,
    ),
  ),
);

Future<PickedProduct?> configureLine(
  BuildContext context,
  WidgetRef ref,
  String owner,
  int productId, {
  int? unitId,
  int? variantId,
  int? priceListId,
  int? customerId,
  bool purchase = false,
  bool inventory = false,
  bool allowZero = false,
  SaleLineRequest? initial,
}) async {
  final product = await ref
      .read(catalogRepositoryProvider)
      .product(owner, productId);
  final db = ref.read(databaseProvider);
  final photoRow = await db
      .customSelect(
        'SELECT image FROM product_photos WHERE owner_id=? AND product_id=?',
        variables: [Variable(owner), Variable(productId)],
      )
      .getSingleOrNull();
  final photo = photoRow?.read<Uint8List>('image');
  final variantPhotos = await ref
      .read(productEditorProvider)
      .photosForVariants(owner, productId);
  final loadedVariants = await db
      .customSelect(
        "SELECT v.id,v.name,a.value AS selling_unit_id,l.value AS label,(SELECT value FROM product_attributes WHERE owner_id=v.owner_id AND product_id=v.product_id AND variant_id=v.id AND name='shared_stock') AS shared_stock,(SELECT value FROM product_attributes WHERE owner_id=v.owner_id AND product_id=v.product_id AND variant_id=v.id AND name='variant_surcharge') AS surcharge FROM product_variants v LEFT JOIN product_attributes a ON a.owner_id=v.owner_id AND a.product_id=v.product_id AND a.variant_id=v.id AND a.name='selling_unit_id' LEFT JOIN product_attributes l ON l.owner_id=v.owner_id AND l.product_id=v.product_id AND l.variant_id=v.id AND l.name='variant_label' WHERE v.owner_id = ? AND v.product_id = ? AND v.active = 1 ORDER BY v.name",
        variables: [Variable(owner), Variable(productId)],
      )
      .get();
  final variants = <QueryRow>[];
  final labels = <String>{};
  for (final row in loadedVariants) {
    final label =
        (row.readNullable<String>('label') ?? row.read<String>('name'))
            .toLowerCase();
    if (row.readNullable<String>('shared_stock') != '1' || labels.add(label)) {
      variants.add(row);
    }
  }
  final modifiers = await db
      .customSelect(
        'SELECT id,name,price FROM product_modifiers WHERE owner_id = ? AND product_id = ? AND active = 1 ORDER BY name',
        variables: [Variable(owner), Variable(productId)],
      )
      .get();
  if (!context.mounted) return null;
  final disabled = purchase || inventory
      ? <int>{}
      : await ProductUnitSettings(db).disabledUnits(owner, productId);
  final orderedUnits =
      product.units.keys.where((id) => !disabled.contains(id)).toList()..sort(
        (a, b) => product.graph.factor(b).compareTo(product.graph.factor(a)),
      );
  if (orderedUnits.isEmpty) {
    throw StateError('Produk tidak memiliki satuan aktif di kasir');
  }
  var unit =
          initial?.unitId ??
          unitId ??
          (purchase || inventory ? product.baseUnitId : orderedUnits.last),
      variant = initial?.variantId ?? variantId;
  if (!orderedUnits.contains(unit)) unit = orderedUnits.last;
  final prices = <int, Money>{};
  if (!purchase && !inventory) {
    for (final id in orderedUnits) {
      try {
        final price = await ref
            .read(catalogRepositoryProvider)
            .resolvePrice(
              owner,
              productId,
              unitId: id,
              quantity: initial?.quantity ?? Rational.one,
              listId: priceListId,
              customerId: customerId,
              atMillis: DateTime.now().millisecondsSinceEpoch,
            );
        prices[id] = price.price;
      } on StateError {
        /* Unpriced units remain unavailable at checkout. */
      }
    }
  }
  if (!context.mounted) return null;
  final productComposition =
      !purchase &&
      !inventory &&
      variants.any((row) => row.readNullable<String>('shared_stock') == '1');
  bool matchesUnit(QueryRow row) => productComposition
      ? row.readNullable<String>('shared_stock') == '1'
      : row.readNullable<String>('selling_unit_id') == null ||
            row.readNullable<String>('selling_unit_id') == '$unit';
  final multipleVariants = !purchase && !inventory;
  final allocateByUnit = initial?.variantInputUnitId != null
      ? initial!.variantInputUnitId != product.baseUnitId
      : initial != null &&
            initial.variantQuantities.values.every(
              (count) =>
                  (count / product.graph.factor(unit)).denominator ==
                  BigInt.one,
            );
  Rational allocationFactor() => productComposition && allocateByUnit
      ? product.graph.factor(unit)
      : Rational.one;
  Rational counterValue(String text) {
    try {
      final value = Rational.parse(text.replaceAll(',', '.'));
      return value.isNegative ? Rational.zero : value;
    } on FormatException {
      return Rational.zero;
    }
  }

  final variantQuantities = {
    for (final row in variants)
      row.read<int>('id'): TextEditingController(
        text:
            ((initial?.variantQuantities[row.read<int>('id')] ??
                        (row.read<int>('id') == variant
                            ? ((initial?.quantity ?? Rational.one) *
                                  (productComposition
                                      ? product.graph.factor(unit)
                                      : Rational.one))
                            : Rational.zero)) /
                    allocationFactor())
                .display,
      ),
  };
  final quantity = TextEditingController(
    text: initial?.quantity.display ?? '1',
  );
  var previousQuantity = counterValue(quantity.text);
  void changeQuantity(Rational next, {bool rewrite = true}) {
    if (productComposition &&
        unit != product.baseUnitId &&
        !previousQuantity.isZero &&
        !next.isZero) {
      for (final controller in variantQuantities.values) {
        controller.text =
            (counterValue(controller.text) * next / previousQuantity).display;
      }
    }
    if (!next.isZero) previousQuantity = next;
    if (rewrite) quantity.text = next.display;
  }

  bool automaticVariantQuantity() =>
      productComposition && (allocateByUnit || unit == product.baseUnitId);
  Rational selectedVariantTotal() => variants
      .where(matchesUnit)
      .fold<Rational>(
        Rational.zero,
        (sum, row) =>
            sum + counterValue(variantQuantities[row.read<int>('id')]!.text),
      );
  void variantsEdited() {
    if (automaticVariantQuantity()) {
      final total = selectedVariantTotal();
      quantity.text = total.display;
      previousQuantity = total;
    }
  }

  void changeUnit(int next) {
    final totalBase = selectedVariantTotal() * allocationFactor();
    final previousFactor = allocationFactor();
    unit = next;
    final nextFactor = allocationFactor();
    if (productComposition) {
      for (final controller in variantQuantities.values) {
        controller.text =
            (counterValue(controller.text) * previousFactor / nextFactor)
                .display;
      }
      quantity.text = totalBase.isZero
          ? '1'
          : (totalBase / product.graph.factor(unit)).display;
      previousQuantity = counterValue(quantity.text);
    }
    variant = null;
  }

  final cost = TextEditingController(text: '0'),
      discount = TextEditingController(
        text: '${initial?.discount?.rupiah ?? 0}',
      );
  final selectedModifiers = {...?initial?.modifierIds};
  String? error;
  final cashier = !purchase && !inventory;
  final headerUnit = orderedUnits.firstWhere(
    prices.containsKey,
    orElse: () => unit,
  );
  Widget buildPicker(
    BuildContext c,
    ScrollController? scrollController,
  ) => StatefulBuilder(
    builder: (c, set) => _LinePickerSurface(
      cashier: cashier,
      title: cashier
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductPhoto(bytes: photo, size: 72, fit: BoxFit.cover),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: Theme.of(c).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (prices[headerUnit] != null)
                        Text(
                          '${rupiah(prices[headerUnit]!.rupiah)} / ${product.units[headerUnit]}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (headerUnit != product.baseUnitId &&
                          prices[product.baseUnitId] != null)
                        Text(
                          '${rupiah(prices[product.baseUnitId]!.rupiah)} / ${product.units[product.baseUnitId]}',
                          style: Theme.of(c).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(c).colorScheme.outlineVariant,
                    ),
                    fixedSize: const Size(38, 38),
                  ),
                ),
              ],
            )
          : Text(product.name),
      content: SizedBox(
        width: cashier ? MediaQuery.sizeOf(c).width : 440,
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height:
                    56 +
                    (MediaQuery.textScalerOf(c).scale(12) - 12).clamp(
                          0,
                          double.infinity,
                        ) *
                        2,
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    expandedInsets: EdgeInsets.zero,
                    key: const ValueKey('line-selling-unit'),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.electricBlue,
                      selectedForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                    segments: [
                      for (final id in orderedUnits)
                        ButtonSegment(
                          value: id,
                          icon: Icon(
                            id == product.baseUnitId
                                ? Icons.storefront_outlined
                                : Icons.inventory_2_outlined,
                            size: 18,
                          ),
                          label: Text(
                            product.units[id]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            key: ValueKey('line-unit-$id'),
                          ),
                        ),
                    ],
                    selected: {unit},
                    onSelectionChanged: (selected) => set(() {
                      changeUnit(selected.single);
                      error = null;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if ((productComposition && unit != product.baseUnitId) ||
                  !multipleVariants ||
                  !variants.any(matchesUnit))
                Row(
                  children: [
                    IconButton.filledTonal(
                      key: const ValueKey('line-quantity-minus'),
                      tooltip: 'Kurangi jumlah',
                      icon: const Icon(Icons.remove),
                      onPressed: () => set(() {
                        final current = counterValue(quantity.text);
                        final minimum = allowZero
                            ? Rational.zero
                            : Rational.one;
                        changeQuantity(
                          current.compareTo(minimum + Rational.one) >= 0
                              ? current - Rational.one
                              : minimum,
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('line-quantity'),
                        controller: quantity,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => set(() {
                          changeQuantity(
                            counterValue(quantity.text),
                            rewrite: false,
                          );
                          error = null;
                        }),
                        decoration: InputDecoration(
                          labelText: 'Jumlah / ${product.units[unit]}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: const ValueKey('line-quantity-plus'),
                      tooltip: 'Tambah jumlah',
                      icon: const Icon(Icons.add),
                      onPressed: () => set(
                        () => changeQuantity(
                          counterValue(quantity.text) + Rational.one,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              if (multipleVariants && variants.any(matchesUnit)) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Varian',
                          style: Theme.of(c).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (productComposition)
                        Flexible(
                          child: Text(
                            automaticVariantQuantity()
                                ? 'Total: ${selectedVariantTotal().display} ${product.units[allocateByUnit ? unit : product.baseUnitId]}${allocateByUnit && unit != product.baseUnitId ? ' (${(selectedVariantTotal() * product.graph.factor(unit)).display} ${product.units[product.baseUnitId]})' : ''}'
                                : '${selectedVariantTotal().display} / ${(counterValue(quantity.text) * product.graph.factor(unit)).display} ${product.units[product.baseUnitId]}',
                            key: const ValueKey('variant-allocation-total'),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Theme.of(c).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final row in variants.where(matchesUnit))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(c).brightness == Brightness.dark
                            ? Theme.of(c).colorScheme.surfaceContainerLow
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(
                            c,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          ProductPhoto(
                            bytes:
                                variantPhotos[row.readNullable<String>(
                                      'label',
                                    ) ??
                                    row.read<String>('name')] ??
                                photo,
                            size: 38,
                            fit: BoxFit.cover,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.readNullable<String>('label') ??
                                      row.read<String>('name'),
                                ),
                                if (prices[productComposition
                                        ? product.baseUnitId
                                        : unit] !=
                                    null)
                                  Text(
                                    '${rupiah((prices[productComposition ? product.baseUnitId : unit]! + Money(int.tryParse(row.readNullable<String>('surcharge') ?? '0') ?? 0)).rupiah)} / ${product.units[productComposition ? product.baseUnitId : unit]}',
                                    style: Theme.of(c).textTheme.bodySmall
                                        ?.copyWith(fontSize: 11),
                                  ),
                                if ((int.tryParse(
                                          row.readNullable<String>(
                                                'surcharge',
                                              ) ??
                                              '0',
                                        ) ??
                                        0) >
                                    0)
                                  Text(
                                    '+ Rp ${row.read<String>('surcharge')} / ${product.units[productComposition ? product.baseUnitId : unit]}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        c,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Kurangi jumlah',
                            icon: const Icon(Icons.remove, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(
                                c,
                              ).colorScheme.surfaceContainerHighest,
                              minimumSize: const Size(34, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => set(() {
                              final controller =
                                  variantQuantities[row.read<int>('id')]!;
                              final current = counterValue(controller.text);
                              controller.text =
                                  current.compareTo(Rational.one) > 0
                                  ? (current - Rational.one).display
                                  : '0';
                              variantsEdited();
                            }),
                          ),
                          SizedBox(
                            width:
                                54 +
                                (MediaQuery.textScalerOf(c).scale(14) - 14)
                                        .clamp(0, double.infinity) *
                                    2,
                            child: TextField(
                              key: ValueKey(
                                'variant-quantity-${row.read<int>('id')}',
                              ),
                              controller:
                                  variantQuantities[row.read<int>('id')],
                              onChanged: (_) => set(() {
                                variantsEdited();
                                error = null;
                              }),
                              textAlign: TextAlign.center,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tambah jumlah',
                            icon: const Icon(Icons.add, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.electricBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(34, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => set(() {
                              final controller =
                                  variantQuantities[row.read<int>('id')]!;
                              final current = counterValue(controller.text);
                              controller.text =
                                  (current + Rational.one).display;
                              variantsEdited();
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (!multipleVariants && variants.any(matchesUnit))
                DropdownButtonFormField<int>(
                  key: ValueKey('line-variant-$unit'),
                  initialValue: variant ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Varian'),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('Standar')),
                    ...variants
                        .where(matchesUnit)
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.read<int>('id'),
                            child: Text(
                              v.readNullable<String>('label') ??
                                  v.read<String>('name'),
                            ),
                          ),
                        ),
                  ],
                  onChanged: (v) => set(() => variant = v == 0 ? null : v),
                ),
              const SizedBox(height: 12),
              if (purchase || !inventory)
                TextField(
                  key: const ValueKey('line-amount'),
                  controller: purchase ? cost : discount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      purchase ? Icons.payments_outlined : Icons.sell_outlined,
                    ),
                    labelText: purchase
                        ? 'Harga beli per satuan (Rp)'
                        : !productComposition &&
                              multipleVariants &&
                              variants.any(matchesUnit)
                        ? 'Diskon per varian (Rp)'
                        : 'Diskon item (Rp)',
                  ),
                ),
              if (!purchase && !inventory)
                for (final modifier in modifiers)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${modifier.read<String>('name')} + ${rupiah(modifier.read<int>('price'))}',
                    ),
                    value: selectedModifiers.contains(modifier.read<int>('id')),
                    onChanged: (v) => set(
                      () => v!
                          ? selectedModifiers.add(modifier.read<int>('id'))
                          : selectedModifiers.remove(modifier.read<int>('id')),
                    ),
                  ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          onPressed: () {
            try {
              final amount = int.parse((purchase ? cost : discount).text);
              if (amount < 0) {
                throw const FormatException('Jumlah atau harga tidak valid');
              }
              if (productComposition) {
                var qty = automaticVariantQuantity()
                    ? Rational.one
                    : Rational.parse(quantity.text.replaceAll(',', '.'));
                fractionRangeCheck(qty);
                if (qty.compareTo(Rational.zero) <= 0) {
                  throw const FormatException('Jumlah harus positif');
                }
                final allocation = <int, Rational>{};
                var total = Rational.zero;
                for (final row in variants.where(matchesUnit)) {
                  final id = row.read<int>('id');
                  final entered = Rational.parse(
                    variantQuantities[id]!.text.replaceAll(',', '.'),
                  );
                  final count = entered * allocationFactor();
                  fractionRangeCheck(count);
                  if (count.isNegative) {
                    throw const FormatException('Jumlah varian tidak valid');
                  }
                  if (!count.isZero) allocation[id] = count;
                  total += count;
                }
                if (automaticVariantQuantity()) {
                  qty = total / product.graph.factor(unit);
                  fractionRangeCheck(qty);
                  if (qty.isZero) {
                    throw const FormatException(
                      'Masukkan jumlah untuk minimal satu varian',
                    );
                  }
                }
                final required = qty * product.graph.factor(unit);
                if (total != required) {
                  set(
                    () => error =
                        'Total varian harus ${required.display} ${product.units[product.baseUnitId]}',
                  );
                  return;
                }
                Navigator.pop(
                  c,
                  PickedProduct(
                    SaleLineRequest(
                      productId: productId,
                      unitId: unit,
                      quantity: qty,
                      variantQuantities: allocation,
                      variantInputUnitId: allocateByUnit
                          ? unit
                          : product.baseUnitId,
                      modifierIds: selectedModifiers.toList()..sort(),
                      discount: Money(amount),
                    ),
                    product.name,
                    Money(0),
                  ),
                );
                return;
              }
              final quantities = multipleVariants && variants.any(matchesUnit)
                  ? {
                      for (final row in variants.where(matchesUnit))
                        row.read<int>('id'): Rational.parse(
                          variantQuantities[row.read<int>('id')]!.text
                              .replaceAll(',', '.'),
                        ),
                    }
                  : <int?, Rational>{
                      variant: Rational.parse(
                        quantity.text.replaceAll(',', '.'),
                      ),
                    };
              final lines = <SaleLineRequest>[];
              for (final entry in quantities.entries) {
                final qty = entry.value;
                fractionRangeCheck(qty);
                if (qty.isNegative) {
                  throw const FormatException('Jumlah tidak valid');
                }
                if (qty.isZero &&
                    multipleVariants &&
                    variants.any(matchesUnit)) {
                  continue;
                }
                if (qty.isZero && !allowZero) {
                  throw const FormatException('Jumlah harus positif');
                }
                lines.add(
                  SaleLineRequest(
                    productId: productId,
                    unitId: unit,
                    variantId: entry.key,
                    quantity: qty,
                    modifierIds: selectedModifiers.toList()..sort(),
                    discount: purchase ? null : Money(amount),
                  ),
                );
              }
              if (lines.isEmpty) {
                set(() => error = 'Masukkan jumlah untuk minimal satu varian');
                return;
              }
              Navigator.pop(
                c,
                PickedProduct(
                  lines.first,
                  product.name,
                  Money(purchase ? amount : 0),
                  additionalLines: lines.skip(1).toList(),
                ),
              );
            } catch (failure) {
              set(
                () => error = failure is FormatException
                    ? failure.message
                    : 'Masukkan jumlah positif dan Rupiah bulat minimal 0',
              );
            }
          },
          label: const Text('Tambahkan'),
        ),
      ],
    ),
  );
  if (!context.mounted) {
    quantity.dispose();
    cost.dispose();
    discount.dispose();
    for (final controller in variantQuantities.values) {
      controller.dispose();
    }
    return null;
  }
  final result = await (cashier
      ? showOperationSheet<PickedProduct>(
          context: context,
          builder: buildPicker,
        )
      : showOperationDialog<PickedProduct>(
          context: context,
          builder: (c) => buildPicker(c, null),
        ));
  quantity.dispose();
  cost.dispose();
  discount.dispose();
  for (final controller in variantQuantities.values) {
    controller.dispose();
  }
  return result;
}

class _LinePickerSurface extends StatelessWidget {
  const _LinePickerSurface({
    required this.cashier,
    required this.title,
    required this.content,
    required this.actions,
  });

  final bool cashier;
  final Widget title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (!cashier) {
      return AlertDialog(title: title, content: content, actions: actions);
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefaultTextStyle(
              style: Theme.of(
                context,
              ).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700),
              child: title,
            ),
            const SizedBox(height: 16),
            Expanded(child: content),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButtonTheme(
                    data: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    child: SizedBox(height: 48, child: actions.first),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(height: 48, child: actions.last),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProductPicker extends ConsumerStatefulWidget {
  const ProductPicker({
    super.key,
    required this.owner,
    this.purchase = false,
    this.inventory = false,
    this.allowZero = false,
  });
  final String owner;
  final bool purchase;
  final bool inventory;
  final bool allowZero;
  @override
  ConsumerState<ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<ProductPicker> {
  final search = TextEditingController();
  String query = '';
  bool selecting = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> select(int id, {int? unitId, int? variantId}) async {
    if (selecting) return;
    selecting = true;
    try {
      final line = await configureLine(
        context,
        ref,
        widget.owner,
        id,
        unitId: unitId,
        variantId: variantId,
        purchase: widget.purchase,
        inventory: widget.inventory,
        allowZero: widget.allowZero,
      );
      if (line != null && mounted) Navigator.pop(context, line);
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
    selecting = false;
  }

  Future<void> barcode(String code) async {
    try {
      final match = await resolveBarcode(context, ref, widget.owner, code);
      if (match != null && mounted) {
        await select(
          match.productId,
          unitId: match.unitId,
          variantId: match.variantId,
        );
      }
    } catch (e) {
      if (mounted) await showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pilih produk')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: search,
            onChanged: (v) => setState(() => query = v.toLowerCase()),
            onSubmitted: barcode,
            decoration: InputDecoration(
              labelText: 'Cari / scan produk',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Scan barcode',
                onPressed: () async {
                  final code = await scanBarcode(context);
                  if (code != null && mounted) await barcode(code);
                },
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
        ),
        Expanded(
          child: ref
              .watch(localProductsProvider(widget.owner))
              .when(
                loading: () => const PageShimmer(),
                error: (e, _) => Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.invalidate(localProductsProvider(widget.owner)),
                    child: const Text('Coba lagi'),
                  ),
                ),
                data: (products) {
                  final items = products
                      .where(
                        (p) =>
                            p.name.toLowerCase().contains(query) ||
                            (p.barcode ?? '').contains(query) ||
                            (p.sku ?? '').toLowerCase().contains(query),
                      )
                      .toList();
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (c, i) => ListTile(
                      leading: ProductPhoto(bytes: items[i].photo),
                      title: Text(items[i].name),
                      subtitle: Text(
                        '${rupiah(items[i].price)} / ${items[i].unit}',
                      ),
                      onTap: () => select(items[i].id!),
                    ),
                  );
                },
              ),
        ),
      ],
    ),
  );
}
