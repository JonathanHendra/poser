import 'dart:typed_data';
import 'dart:async';
import '../../cloud/application/cloud_sync.dart';
import 'package:flutter/material.dart';
import '../../../core/ads/interstitial_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/domain/rational.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/application/business_providers.dart';
import '../../business/domain/business_repository.dart';
import '../../catalog/application/catalog_providers.dart';
import '../application/product_photo_picker.dart';
import '../application/product_photo_permissions.dart';
import '../data/product_editor_repository.dart';
import '../domain/product_unit_hierarchy.dart';
import 'product_photo.dart';
import '../../barcode/presentation/scanner.dart';

Future<void> showProductForm(
  BuildContext context,
  String owner, {
  LocalProduct? product,
  String? initialBarcode,
}) {
  if (product == null) unawaited(InterstitialAds.instance.initialize());
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProductForm(
      owner: owner,
      product: product,
      initialBarcode: initialBarcode,
    ),
  );
}

class ProductForm extends ConsumerStatefulWidget {
  const ProductForm({
    super.key,
    required this.owner,
    this.product,
    this.initialBarcode,
  });
  final String owner;
  final LocalProduct? product;
  final String? initialBarcode;
  @override
  ConsumerState<ProductForm> createState() => _ProductFormState();
}

class _UnitInput {
  _UnitInput(this.id);
  final int id;
  final name = TextEditingController(),
      price = TextEditingController(),
      buyPrice = TextEditingController(),
      count = TextEditingController(),
      stock = TextEditingController(text: '0');
  void dispose() {
    for (final controller in [name, price, buyPrice, count, stock]) {
      controller.dispose();
    }
  }

  bool cashierActive = true;
}

class _ProductFormState extends ConsumerState<ProductForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      unit = TextEditingController(),
      sku = TextEditingController(),
      barcode = TextEditingController(),
      price = TextEditingController();
  final levels = [_UnitInput(0)];
  int nextUnitId = 1;
  final brand = TextEditingController(), description = TextEditingController();
  String category = '';
  final categoryController = TextEditingController();
  final categoryFocus = FocusNode();
  final productVariants = <String>[];
  final variantPrices = <String, int>{};
  final variantPhotos = <String, Uint8List?>{};
  int step = 0;
  bool metadataLoaded = false;
  Uint8List? photo;
  bool saving = false, picking = false;
  String? error;
  bool get editing => widget.product != null;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    barcode.text = widget.initialBarcode ?? '';
    if (p != null) {
      name.text = p.name;
      unit.text = p.unit;
      price.text = '${p.price}';
      sku.text = p.sku ?? '';
      barcode.text = p.barcode ?? '';
      photo = p.photo;
      category = p.category ?? 'Lainnya';
      categoryController.text = category;
    }
    unit.addListener(refreshLabels);
    if (p != null) loadMetadata();
  }

  Future<void> loadMetadata() async {
    try {
      final data = await ref.read(
        productMetadataProvider((widget.owner, widget.product!.id!)).future,
      );
      final variants = await ref.read(
        productVariantsProvider((widget.owner, widget.product!.id!)).future,
      );
      final surcharges = await ref.read(
        productVariantSurchargesProvider((
          widget.owner,
          widget.product!.id!,
        )).future,
      );
      final photos = await ref
          .read(productEditorProvider)
          .photosForVariants(widget.owner, widget.product!.id!);
      if (!mounted) return;
      setState(() {
        category = data['category']!.isEmpty ? 'Lainnya' : data['category']!;
        categoryController.text = category;
        productVariants.addAll(variants);
        variantPrices.addAll(surcharges);
        variantPhotos.addAll(photos);
        brand.text = data['brand']!;
        description.text = data['description']!;
        metadataLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Informasi produk belum dapat dibuka. Tutup lalu coba lagi.',
        );
      }
    }
  }

  void refreshLabels() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    categoryFocus.dispose();
    for (final c in [
      name,
      unit,
      sku,
      barcode,
      price,
      brand,
      description,
      categoryController,
    ]) {
      c.dispose();
    }
    for (final level in levels) {
      level.dispose();
    }
    super.dispose();
  }

  String get baseLabel =>
      unit.text.trim().isEmpty ? 'satuan dasar' : unit.text.trim();

  Future<void> showPhotoError(String message, {bool settings = false}) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          settings ? 'Izin foto dan kamera' : 'Foto belum dapat dibuka',
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tutup'),
          ),
          if (settings)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Buka pengaturan'),
            ),
        ],
      ),
    );
    if (open == true && mounted) {
      try {
        if (!await ref.read(productPhotoPickerProvider).openSettings() &&
            mounted) {
          setState(
            () => error =
                'Pengaturan belum dapat dibuka. Buka izin aplikasi dari pengaturan perangkat.',
          );
        }
      } catch (_) {
        if (mounted) setState(() => error = 'Pengaturan belum dapat dibuka.');
      }
    }
  }

  Future<void> pick(ImageSource source) async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final image = await ref.read(productPhotoPickerProvider).pick(source);
      if (mounted && image != null) setState(() => photo = image);
    } on ProductPhotoPermissionException catch (e) {
      if (mounted) {
        setState(() => error = e.message);
        await showPhotoError(e.message, settings: e.canOpenSettings);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Foto belum dapat dipilih.',
        );
        await showPhotoError(error!);
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Widget field(
    TextEditingController controller,
    String label,
    String key, {
    bool money = false,
    bool quantity = false,
    bool optional = false,
    bool readOnly = false,
    Widget? suffix,
    int maxLines = 1,
    bool conversion = false,
    bool uniqueUnit = false,
  }) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    enabled: !saving && !picking,
    readOnly: readOnly,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label, suffixIcon: suffix),
    keyboardType: money
        ? TextInputType.number
        : quantity
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    onChanged: (_) => setState(() => error = null),
    validator: (v) {
      final value = v?.trim() ?? '';
      if (value.isEmpty) return optional ? null : 'Wajib diisi';
      if (money) {
        final n = int.tryParse(value);
        if (n == null || n < 0 || n > maxExactInteger) {
          return 'Masukkan Rupiah bulat, minimal 0';
        }
      }
      if (quantity) {
        try {
          final n = Rational.parse(value.replaceAll(',', '.'));
          fractionRangeCheck(n);
          if (n.isNegative || (conversion && n.compareTo(Rational.one) < 0)) {
            return 'Jumlah tidak valid';
          }
        } catch (_) {
          return 'Masukkan desimal atau pecahan yang valid';
        }
      }
      if (uniqueUnit &&
          levels
                  .where(
                    (level) =>
                        level.name.text.trim().toLowerCase() ==
                        value.toLowerCase(),
                  )
                  .length >
              1) {
        return 'Nama satuan sudah digunakan';
      }
      return null;
    },
  );

  Widget fields(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      final two = constraints.maxWidth >= 560;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children)
            SizedBox(
              width: two
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth,
              child: child,
            ),
        ],
      );
    },
  );

  Future<void> save() async {
    if (saving || picking || !(form.currentState?.validate() ?? false)) return;
    if (editing && !metadataLoaded) return;
    if (ref.read(authProvider).user?.uid != widget.owner) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final hierarchy = editing ? null : readHierarchy();
      final qty = hierarchy?.totalStock ?? Rational.zero;
      final id = await ref
          .read(productEditorProvider)
          .save(
            widget.owner,
            LocalProduct(
              id: widget.product?.id,
              name: name.text,
              unit: hierarchy?.base.name ?? unit.text,
              price: hierarchy?.base.price ?? int.parse(price.text.trim()),
              stock: 0,
              exactStock: qty,
              sku: sku.text.trim().isEmpty ? null : sku.text.trim(),
              barcode: barcode.text.trim().isEmpty ? null : barcode.text.trim(),
              photo: photo,
              productType: widget.product?.productType ?? 'goods',
            ),
            unitHierarchy: hierarchy,
            category: categoryController.text.trim(),
            productVariants: productVariants,
            variantPrices: variantPrices,
            variantPhotos: variantPhotos,
            brand: brand.text,
            description: description.text,
          );
      unawaited(ref.read(cloudSyncProvider).syncAfterChange(widget.owner));
      ref.invalidate(localProductsProvider(widget.owner));
      ref.invalidate(catalogDetailProvider((widget.owner, id)));
      ref.invalidate(productPhotoProvider((widget.owner, id)));
      ref.invalidate(productMetadataProvider((widget.owner, id)));
      ref.invalidate(productRetailPricesProvider(widget.owner));
      ref.invalidate(productCategoriesProvider(widget.owner));
      ref.invalidate(productUnitVariantsProvider((widget.owner, id)));
      ref.invalidate(productVariantsProvider((widget.owner, id)));
      ref.invalidate(productVariantSurchargesProvider((widget.owner, id)));
      if (mounted) {
        Navigator.pop(context);
        if (!editing) {
          unawaited(InterstitialAds.instance.showIfReady());
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is FormatException
              ? e.message
              : 'Produk belum tersimpan. Periksa SKU/barcode agar tidak duplikat, lalu coba lagi.';
        });
      }
    }
  }

  Widget section(String title, List<Widget> children, {Widget? action}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      );

  Widget basic(bool busy, Uint8List? recovered) => section('Informasi Dasar', [
    AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Theme.of(context).brightness == Brightness.dark
              ? null
              : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: Theme.of(context).brightness == Brightness.dark
              ? [
                  BoxShadow(
                    color: AppColors.electricBlue.withValues(alpha: .28),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ProductPhoto(bytes: photo, size: null, fit: BoxFit.cover),
        ),
      ),
    ),
    const SizedBox(height: 8),
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: busy ? null : () => pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text('Galeri'),
        ),
        if (ref.read(productPhotoPickerProvider).cameraSupported)
          TextButton.icon(
            onPressed: busy ? null : () => pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Kamera'),
          ),
        if (photo != null)
          IconButton(
            tooltip: 'Hapus foto',
            onPressed: busy ? null : () => setState(() => photo = null),
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    if (recovered != null)
      TextButton(
        onPressed: busy
            ? null
            : () {
                setState(() => photo = recovered);
                ref.invalidate(recoveredProductPhotoProvider);
              },
        child: const Text('Gunakan foto yang dipulihkan'),
      ),
    const SizedBox(height: 16),
    field(name, 'Nama produk *', 'product-name'),
    const SizedBox(height: 16),
    LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        textEditingController: categoryController,
        focusNode: categoryFocus,
        optionsBuilder: (value) =>
            {
              ...?ref.read(productCategoriesProvider(widget.owner)).valueOrNull,
              'Rokok',
              'Minuman',
              'Makanan',
              'Sembako',
              'Kebutuhan Rumah',
              'Lainnya',
            }.where(
              (name) =>
                  name.toLowerCase().contains(value.text.trim().toLowerCase()),
            ),
        fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
          key: const ValueKey('product-category'),
          controller: controller,
          focusNode: focus,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Kategori *',
            hintText: 'Nama kategori',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Kategori wajib diisi'
              : null,
          onFieldSubmitted: (_) => submit(),
        ),
        optionsViewBuilder: (context, select, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: constraints.maxWidth,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: options
                      .map(
                        (option) => ListTile(
                          title: Text(option),
                          onTap: () => select(option),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    const SizedBox(height: 16),
    field(brand, 'Merek (opsional)', 'product-brand', optional: true),
    const SizedBox(height: 16),
    field(sku, 'SKU (opsional)', 'product-sku', optional: true),
    const SizedBox(height: 16),
    field(
      barcode,
      'Barcode (opsional)',
      'product-barcode',
      optional: true,
      suffix: IconButton(
        tooltip: 'Scan barcode',
        onPressed: busy
            ? null
            : () async {
                final code = await scanBarcode(context);
                if (code != null && mounted) {
                  setState(() => barcode.text = code);
                }
              },
        icon: const Icon(Icons.qr_code_scanner),
      ),
    ),
    const SizedBox(height: 16),
    field(
      description,
      'Deskripsi (opsional)',
      'product-description',
      optional: true,
      maxLines: 3,
    ),
  ]);

  ProductUnitHierarchy readHierarchy({bool includeStock = true}) =>
      ProductUnitHierarchy([
        for (var i = 0; i < levels.length; i++)
          ProductUnitLevel(
            name: levels[i].name.text.trim(),
            price:
                levels[i].price.text.trim().isEmpty && !levels[i].cashierActive
                ? 0
                : int.parse(levels[i].price.text.trim()),
            buyPrice: levels[i].buyPrice.text.trim().isEmpty
                ? null
                : int.parse(levels[i].buyPrice.text.trim()),
            cashierActive: levels[i].cashierActive,
            unitsInParent: i == 0
                ? Rational.one
                : Rational.parse(levels[i].count.text.replaceAll(',', '.')),
            stock: includeStock
                ? Rational.parse(levels[i].stock.text.replaceAll(',', '.'))
                : Rational.zero,
          ),
      ]);

  void addUnit(int index) {
    setState(() {
      levels.insert(index + 1, _UnitInput(nextUnitId++));
      if (index + 2 < levels.length) levels[index + 2].count.clear();
      error = null;
    });
  }

  void removeUnit(int index) {
    final removed = levels.removeAt(index);
    if (index < levels.length) levels[index].count.clear();
    setState(() => error = null);
    // The removed field widgets must unmount before their controllers are disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Widget variantChips(bool busy) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in productVariants)
          InputChip(
            avatar: ProductPhoto(bytes: variantPhotos[name], size: 28),
            label: Text(
              (variantPrices[name] ?? 0) > 0
                  ? '$name + Rp ${variantPrices[name]}'
                  : name,
            ),
            onPressed: busy ? null : () => addVariant(existing: name),
            onDeleted: busy
                ? null
                : () => setState(() {
                    productVariants.remove(name);
                    variantPrices.remove(name);
                    variantPhotos.remove(name);
                  }),
          ),
      ],
    ),
  );

  Future<void> addVariant({String? existing}) async {
    var draft = existing ?? '';
    var surcharge = existing == null ? '' : '${variantPrices[existing] ?? 0}';
    final variantForm = GlobalKey<FormState>();
    Uint8List? draftPhoto = variantPhotos[existing];
    var uploading = false;
    String? photoError;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'Tambah varian' : 'Edit varian'),
          content: Form(
            key: variantForm,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProductPhoto(bytes: draftPhoto, size: 80),
                  Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Upload foto varian',
                        icon: uploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.photo_library_outlined),
                        onPressed: uploading
                            ? null
                            : () async {
                                update(() {
                                  uploading = true;
                                  photoError = null;
                                });
                                try {
                                  final bytes = await ref
                                      .read(productPhotoPickerProvider)
                                      .pick(ImageSource.gallery);
                                  if (context.mounted && bytes != null) {
                                    update(() => draftPhoto = bytes);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    update(
                                      () => photoError =
                                          e is ProductPhotoPermissionException
                                          ? e.message
                                          : 'Foto belum dapat dipilih.',
                                    );
                                  }
                                } finally {
                                  if (context.mounted) {
                                    update(() => uploading = false);
                                  }
                                }
                              },
                      ),
                      if (draftPhoto != null)
                        IconButton(
                          tooltip: 'Hapus foto varian',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: uploading
                              ? null
                              : () => update(() => draftPhoto = null),
                        ),
                    ],
                  ),
                  if (photoError != null)
                    Text(
                      photoError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  TextFormField(
                    initialValue: draft,
                    autofocus: true,
                    onChanged: (value) => draft = value,
                    decoration: const InputDecoration(
                      labelText: 'Nama varian',
                      hintText: 'Coklat',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Isi nama varian'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: surcharge,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Harga varian (opsional)',
                      prefixText: 'Rp ',
                    ),
                    onChanged: (value) => surcharge = value.trim(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final amount = int.tryParse(value.trim());
                      return amount == null ||
                              amount < 0 ||
                              amount > maxExactInteger
                          ? 'Harga tidak valid'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: uploading
                  ? null
                  : () {
                      if (variantForm.currentState!.validate()) {
                        Navigator.pop(context, draft.trim());
                      }
                    },
              child: Text(existing == null ? 'Tambah' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        value != null &&
        !productVariants.any(
          (name) =>
              name != existing && name.toLowerCase() == value.toLowerCase(),
        )) {
      setState(() {
        if (existing != null) {
          productVariants.remove(existing);
          variantPrices.remove(existing);
          variantPhotos.remove(existing);
        }
        productVariants.add(value);
        variantPrices[value] = int.tryParse(surcharge) ?? 0;
        variantPhotos[value] = draftPhoto;
      });
    }
  }

  Future<void> showUnitsInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Satuan & Varian'),
      content: SingleChildScrollView(child: Text(unitsInfo)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Mengerti'),
        ),
      ],
    ),
  );

  String get unitsInfo =>
      '${editing ? 'Bagian Daftar satuan menampilkan satuan dasar stok dan mengatur harga jual produk per satuan tersebut.' : 'Bagian Daftar satuan digunakan untuk mengatur satuan produk, hubungan jumlah antar satuan, serta harga jual dan harga beli masing-masing satuan.\n\nSusun satuan dari kemasan terbesar ke terkecil. Contoh: Dus lalu Pcs, dengan 12 Pcs dalam 1 Dus. Stok akan dihitung berdasarkan konversi tersebut.\n\nAktifkan “Tampilkan di kasir” agar satuan bisa dipilih saat penjualan. Gunakan “Tambah Satuan” untuk menambahkan satuan berikutnya.'}'
      '\n\nVarian\n'
      'Gunakan “+ Varian” untuk menambahkan pilihan produk, seperti rasa atau warna.\n\n'
      'Jika harga varian dikosongkan atau diisi 0, varian menggunakan harga jual satuan tanpa biaya tambahan.\n\n'
      'Jika harga varian diisi lebih dari 0, nilai tersebut menjadi tambahan pada harga jual, dihitung sesuai jumlah varian yang dibeli. Contoh: harga jual Rp 10.000 dengan tambahan varian Rp 2.000 menjadi Rp 12.000 untuk satu buah.';

  Widget units(bool busy) {
    final addVariantButton = TextButton.icon(
      key: const ValueKey('product-add-variant'),
      onPressed: busy ? null : addVariant,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Varian'),
    );
    if (editing) {
      return section('Daftar satuan', [
        field(unit, 'Satuan dasar stok', 'product-unit', readOnly: true),
        const SizedBox(height: 16),
        field(price, 'Harga / $baseLabel (Rp)', 'product-price', money: true),
        if (productVariants.isNotEmpty) variantChips(busy),
      ], action: addVariantButton);
    }
    return section('Daftar satuan', [
      if (productVariants.isNotEmpty) variantChips(busy),
      for (var i = 0; i < levels.length; i++) ...[
        Container(
          key: ValueKey('unit-level-${levels[i].id}'),
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: AppColors.electricBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Satuan ${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (i > 0)
                    IconButton(
                      tooltip: 'Hapus satuan',
                      onPressed: busy ? null : () => removeUnit(i),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                ],
              ),
              CheckboxListTile(
                key: ValueKey('unit-cashier-${levels[i].id}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Tampilkan di kasir'),
                value: levels[i].cashierActive,
                onChanged: busy
                    ? null
                    : (value) =>
                          setState(() => levels[i].cashierActive = value!),
              ),
              const SizedBox(height: 12),
              field(
                levels[i].name,
                'Nama satuan *',
                'unit-name-${levels[i].id}',
                uniqueUnit: true,
              ),
              if (i > 0) ...[
                const SizedBox(height: 16),
                field(
                  levels[i].count,
                  'Jumlah ${levels[i].name.text.trim().isEmpty ? 'satuan ini' : levels[i].name.text.trim()} dalam 1 ${levels[i - 1].name.text.trim().isEmpty ? 'satuan sebelumnya' : levels[i - 1].name.text.trim()} *',
                  'unit-count-${levels[i].id}',
                  quantity: true,
                  conversion: true,
                ),
              ],
              const SizedBox(height: 16),
              field(
                levels[i].price,
                levels[i].cashierActive
                    ? 'Harga jual *'
                    : 'Harga jual (opsional)',
                'unit-price-${levels[i].id}',
                money: true,
                optional: !levels[i].cashierActive,
              ),
              const SizedBox(height: 16),
              field(
                levels[i].buyPrice,
                levels[i].cashierActive
                    ? 'Harga beli (opsional)'
                    : 'Harga beli *',
                'unit-buy-price-${levels[i].id}',
                money: true,
                optional: levels[i].cashierActive,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: ValueKey('add-unit-${levels[i].id}'),
                onPressed: busy ? null : () => addUnit(i),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah Satuan'),
              ),
            ],
          ),
        ),
      ],
    ], action: addVariantButton);
  }

  Widget stockSection(bool busy) {
    if (editing) {
      return section('Stok', [
        Text(
          'Stok: ${widget.product!.stock.display} $baseLabel',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ]);
    }
    Rational? total;
    try {
      total = readHierarchy().totalStock;
    } catch (_) {}
    return section('Stok', [
      for (final level in levels) ...[
        field(
          level.stock,
          'Stok ${level.name.text.trim().isEmpty ? 'satuan ${levels.indexOf(level) + 1}' : level.name.text.trim()}',
          'unit-stock-${level.id}',
          quantity: true,
        ),
        const SizedBox(height: 16),
      ],
      if (total != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            'Total stok: ${total.display} ${levels.last.name.text.trim()}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(productCategoriesProvider(widget.owner));
    final busy = saving || picking;
    final wide =
        MediaQuery.sizeOf(context).width >= 900 &&
        MediaQuery.textScalerOf(context).scale(14) < 22;
    final recovered = ref.watch(recoveredProductPhotoProvider).valueOrNull;
    final content = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          wide
              ? (editing ? 'Edit Produk' : 'Tambah Produk')
              : [
                  '${editing ? 'Edit' : 'Tambah'} Produk',
                  'Satuan & Varian',
                  'Stok',
                ][step],
          style: Theme.of(context).textTheme.titleMedium,
        ),
        leading: IconButton(
          tooltip: step > 0 && !wide ? 'Kembali' : 'Tutup',
          onPressed: busy
              ? null
              : () {
                  if (step > 0 && !wide) {
                    setState(() => step--);
                  } else {
                    Navigator.pop(context);
                  }
                },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (wide)
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
          if (wide || step == 1)
            IconButton(
              tooltip: 'Info satuan',
              onPressed: showUnitsInfo,
              icon: const Icon(Icons.info_outline),
            ),
          if (wide || step != 1)
            IconButton(
              tooltip: wide ? 'Simpan produk' : 'Lanjutkan',
              onPressed: busy ? null : () => advance(wide),
              icon: const Icon(Icons.check, color: AppColors.electricBlue),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: basic(busy, recovered)),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            units(busy),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 20),
                            stockSection(busy),
                          ],
                        ),
                      ),
                    ],
                  )
                else if (step == 0)
                  basic(busy, recovered)
                else if (step == 1)
                  units(busy)
                else
                  stockSection(busy),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: FilledButton.icon(
              onPressed: busy ? null : () => advance(wide),
              icon: Icon(
                wide || step == 2 ? Icons.save_outlined : Icons.arrow_forward,
              ),
              label: Text(wide || step == 2 ? 'Simpan produk' : 'Lanjutkan'),
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !busy,
      child: wide
          ? Dialog(
              child: SizedBox(
                width: 1000,
                height: MediaQuery.sizeOf(context).height * 0.92,
                child: content,
              ),
            )
          : Dialog.fullscreen(child: content),
    );
  }

  void advance(bool wide) {
    if (!(form.currentState?.validate() ?? false)) return;
    if (!editing && (wide || step == 1)) {
      try {
        readHierarchy(includeStock: false);
      } catch (e) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Periksa urutan satuan dan konversi.',
        );
        return;
      }
    }
    if (wide || step == 2) {
      save();
    } else {
      setState(() => step++);
    }
  }
}
