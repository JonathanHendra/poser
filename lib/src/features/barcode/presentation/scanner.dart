import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../products/application/product_photo_permissions.dart';
import '../../products/presentation/product_form.dart';
import '../../catalog/application/catalog_providers.dart';
import '../data/barcode_repository.dart';

abstract interface class ScannerService {
  Future<String?> scan();
}

class CameraScannerService implements ScannerService {
  CameraScannerService(this.context);
  final BuildContext context;
  @override
  Future<String?> scan() async {
    await ProductPhotoPermissions().ensureCamera();
    if (!context.mounted) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeCameraScreen()),
    );
  }
}

class ExternalScannerService implements ScannerService {
  ExternalScannerService(this.input);
  final Stream<String> input;
  @override
  Future<String?> scan() =>
      input.where((s) => s.trim().isNotEmpty).map((s) => s.trim()).first;
}

final barcodeRepositoryProvider = Provider(
  (ref) => BarcodeRepository(ref.watch(catalogRepositoryProvider)),
);

class BarcodeCameraScreen extends StatefulWidget {
  const BarcodeCameraScreen({super.key});
  @override
  State<BarcodeCameraScreen> createState() => _BarcodeCameraScreenState();
}

class _BarcodeCameraScreenState extends State<BarcodeCameraScreen> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool finished = false;
  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scan barcode'),
      actions: [
        IconButton(
          tooltip: 'Lampu kamera',
          onPressed: controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_outlined),
        ),
      ],
    ),
    body: MobileScanner(
      controller: controller,
      onDetect: (capture) {
        if (finished) return;
        final codes = capture.barcodes
            .map((b) => b.rawValue)
            .whereType<String>()
            .where((v) => v.trim().isNotEmpty);
        if (codes.isNotEmpty) {
          finished = true;
          Navigator.pop(context, codes.first.trim());
        }
      },
    ),
  );
}

Future<String?> scanBarcode(BuildContext context) async {
  try {
    return await CameraScannerService(context).scan();
  } catch (e) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Kamera tidak tersedia'),
          content: Text(
            e is ProductPhotoPermissionException
                ? e.message.replaceAll(
                    'mengambil foto produk',
                    'memindai barcode',
                  )
                : 'Kamera belum dapat dibuka. Periksa izin kamera dan coba lagi.',
          ),
          actions: [
            if (e is ProductPhotoPermissionException && e.canOpenSettings)
              TextButton(
                onPressed: () async {
                  Navigator.pop(c);
                  await ProductPhotoPermissions().openSettings();
                },
                child: const Text('Pengaturan'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
    return null;
  }
}

Future<BarcodeMatch?> resolveBarcode(
  BuildContext context,
  WidgetRef ref,
  String owner,
  String code,
) async {
  final match = await ref.read(barcodeRepositoryProvider).lookup(owner, code);
  if (match != null || !context.mounted) return match;
  final action = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Barcode tidak ditemukan'),
      content: Text(code),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, 'search'),
          child: const Text('Cari produk'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'add'),
          child: const Text('Tambah produk'),
        ),
      ],
    ),
  );
  if (action == 'add' && context.mounted) {
    await showProductForm(context, owner, initialBarcode: code);
    if (!context.mounted) return null;
    return ref.read(barcodeRepositoryProvider).lookup(owner, code);
  }
  return null;
}
