import '../../../core/widgets/page_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/widgets/ad_banner.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../barcode/presentation/scanner.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../application/product_display.dart';
import 'add_to_cashier.dart';
import 'product_form.dart';
import 'product_photo.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({
    super.key,
    this.cashier = false,
    this.title = 'Produk',
  });
  final bool cashier;
  final String title;
  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String query = '';
  String? category;
  String sort = 'latest';
  bool adding = false;

  IconData categoryIcon(String? value) {
    final name = value?.toLowerCase() ?? '';
    if (name.contains('makan')) return Icons.restaurant_outlined;
    if (name.contains('minum')) return Icons.local_drink_outlined;
    if (name.contains('rokok')) return Icons.link_outlined;
    if (name.contains('sembako')) return Icons.shopping_basket_outlined;
    if (name.contains('rumah')) return Icons.home_work_outlined;
    if (value == null) return Icons.grid_view_rounded;
    return Icons.inventory_2_outlined;
  }

  Future<void> barcode(String owner, String code) async {
    try {
      final match = await resolveBarcode(context, ref, owner, code);
      if (match != null && mounted) {
        context.push('/products/${match.productId}');
      }
    } catch (error) {
      if (mounted) await showFailure(context, error);
    }
  }

  Future<void> add(String owner, int id) async {
    if (adding) return;
    setState(() => adding = true);
    await addProductToCashier(context, ref, owner, id);
    if (mounted) setState(() => adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(authProvider).user?.uid;
    if (owner == null) return const SizedBox.shrink();
    final currency =
        ref.watch(businessProfileProvider(owner)).valueOrNull?.currency ??
        'IDR';
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: widget.cashier ? null : 82,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(context, widget.cashier ? 'Kasir' : widget.title),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (!widget.cashier) ...[
              const SizedBox(height: 2),
              Text(
                tr(context, 'Kelola produk, stok, dan harga'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!widget.cashier && wide)
            FilledButton.icon(
              onPressed: () => showProductForm(context, owner),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr(context, 'Tambah Produk')),
            ),
          if (!widget.cashier && !wide)
            IconButton(
              tooltip: tr(context, 'Tambah produk'),
              onPressed: () => showProductForm(context, owner),
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.electricBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
              icon: const Icon(Icons.add, size: 26),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: TextField(
                      onChanged: (value) =>
                          setState(() => query = value.toLowerCase().trim()),
                      onSubmitted: (value) => barcode(owner, value),
                      decoration: InputDecoration(
                        hintText: tr(context, 'Cari produk / scan barcode'),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          borderSide: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkFieldBorder
                                : AppColors.navy,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          borderSide: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkFieldFocusedBorder
                                : AppColors.navy,
                            width: 1.5,
                          ),
                        ),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(5),
                          child: IconButton(
                            tooltip: tr(context, 'Scan barcode'),
                            onPressed: () async {
                              final code = await scanBarcode(context);
                              if (code != null && mounted) {
                                await barcode(owner, code);
                              }
                            },
                            style: IconButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              minimumSize: const Size(42, 42),
                            ),
                            icon: const Icon(Icons.qr_code_scanner),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ref
                  .watch(productDisplayProvider(owner))
                  .when(
                    loading: () => const PageShimmer(),
                    error: (_, _) => AppErrorState(
                      onRetry: () =>
                          ref.invalidate(productDisplayProvider(owner)),
                    ),
                    data: (entries) {
                      final categories =
                          entries
                              .map((e) => e.product.category)
                              .whereType<String>()
                              .toSet()
                              .toList()
                            ..sort();
                      final results = entries
                          .where(
                            (e) =>
                                (category == null ||
                                    e.product.category == category) &&
                                (e.product.name.toLowerCase().contains(query) ||
                                    (e.product.barcode ?? '').contains(query) ||
                                    (e.product.sku ?? '')
                                        .toLowerCase()
                                        .contains(query)),
                          )
                          .toList();
                      switch (sort) {
                        case 'name':
                          results.sort(
                            (a, b) => a.product.name.toLowerCase().compareTo(
                              b.product.name.toLowerCase(),
                            ),
                          );
                          break;
                        case 'stock':
                          results.sort(
                            (a, b) =>
                                b.product.stock.compareTo(a.product.stock),
                          );
                          break;
                        default:
                          results.sort(
                            (a, b) => (b.product.id ?? 0).compareTo(
                              a.product.id ?? 0,
                            ),
                          );
                          break;
                      }
                      return Column(
                        children: [
                          SizedBox(
                            height:
                                56 +
                                (MediaQuery.textScalerOf(context).scale(12) -
                                            12)
                                        .clamp(0, double.infinity) *
                                    2,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 5,
                              ),
                              children: <Widget>[
                                ...[null, ...categories].map(
                                  (value) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      avatar: Icon(
                                        categoryIcon(value),
                                        size: 16,
                                        color: category == value
                                            ? Colors.white
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                      label: Text(
                                        tr(context, value ?? 'Semua'),
                                      ),
                                      selected: category == value,
                                      showCheckmark: false,
                                      selectedColor: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        color: category == value
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                      side: BorderSide.none,
                                      onSelected: (_) =>
                                          setState(() => category = value),
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: tr(context, 'Filter kategori'),
                                  icon: const Icon(Icons.filter_alt_outlined),
                                  onSelected: (value) => setState(
                                    () => category = value == '__all__'
                                        ? null
                                        : value,
                                  ),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: '__all__',
                                      child: Text(
                                        tr(context, 'Semua kategori'),
                                      ),
                                    ),
                                    ...categories.map(
                                      (value) => PopupMenuItem(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 2, 10, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${tr(context, 'Total')} ${results.length} ${tr(context, 'produk')}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: tr(context, 'Urutkan produk'),
                                  initialValue: sort,
                                  onSelected: (value) =>
                                      setState(() => sort = value),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'latest',
                                      child: Text(tr(context, 'Terbaru')),
                                    ),
                                    PopupMenuItem(
                                      value: 'name',
                                      child: Text(tr(context, 'Nama A-Z')),
                                    ),
                                    PopupMenuItem(
                                      value: 'stock',
                                      child: Text(
                                        tr(context, 'Stok terbanyak'),
                                      ),
                                    ),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          switch (sort) {
                                            'name' => tr(context, 'Nama A-Z'),
                                            'stock' => tr(context, 'Stok'),
                                            _ => tr(context, 'Terbaru'),
                                          },
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.keyboard_arrow_down,
                                          size: 18,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: results.isEmpty
                                ? AppEmptyState(
                                    title: entries.isEmpty
                                        ? tr(context, 'Belum ada produk')
                                        : tr(context, 'Produk tidak ditemukan'),
                                    message: entries.isEmpty
                                        ? tr(
                                            context,
                                            'Tambahkan produk toko Anda.',
                                          )
                                        : tr(
                                            context,
                                            'Coba nama atau kategori lain.',
                                          ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, size) {
                                      return ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          0,
                                          12,
                                          112,
                                        ),
                                        itemCount:
                                            results.length +
                                            (!widget.cashier &&
                                                    results.length > 4
                                                ? 1
                                                : 0),
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (context, index) {
                                          if (!widget.cashier &&
                                              results.length > 4 &&
                                              index == 4) {
                                            return const AdBanner();
                                          }
                                          final productIndex =
                                              !widget.cashier &&
                                                  results.length > 4 &&
                                                  index > 4
                                              ? index - 1
                                              : index;
                                          final entry = results[productIndex];
                                          final p = entry.product;
                                          final dark =
                                              Theme.of(context).brightness ==
                                              Brightness.dark;
                                          return Material(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                            elevation: dark ? 0 : 2,
                                            shadowColor: Colors.black
                                                .withValues(alpha: .12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              side: BorderSide(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outlineVariant
                                                    .withValues(
                                                      alpha: dark ? .30 : .18,
                                                    ),
                                              ),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: InkWell(
                                              onTap: () => context.push(
                                                '/products/${p.id}',
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    ProductPhoto(
                                                      bytes: p.photo,
                                                      size: 96,
                                                      fit: BoxFit.cover,
                                                    ),
                                                    const SizedBox(width: 14),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            p.name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 4,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical: 4,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .primaryContainer,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      999,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                p.category ??
                                                                    'Lainnya',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onPrimaryContainer,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 3,
                                                          ),
                                                          for (final price
                                                              in entry.prices
                                                                  .take(2))
                                                            Text(
                                                              '${formatCurrency(price.$2, currency)} / ${price.$1}',
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    price ==
                                                                        entry
                                                                            .prices
                                                                            .first
                                                                    ? FontWeight
                                                                          .w800
                                                                    : FontWeight
                                                                          .w400,
                                                                color:
                                                                    price ==
                                                                        entry
                                                                            .prices
                                                                            .first
                                                                    ? Theme.of(
                                                                        context,
                                                                      ).colorScheme.onSurface
                                                                    : Theme.of(
                                                                        context,
                                                                      ).colorScheme.onSurfaceVariant,
                                                              ),
                                                            ),
                                                          const SizedBox(
                                                            height: 3,
                                                          ),
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .inventory_2,
                                                                size: 14,
                                                                color:
                                                                    AppStatusColors.of(
                                                                      context,
                                                                    ).success,
                                                              ),
                                                              const SizedBox(
                                                                width: 5,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  'Stok: ${entry.stockLabel}',
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Theme.of(
                                                                      context,
                                                                    ).colorScheme.onSurfaceVariant,
                                                                  ),
                                                                ),
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
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
