import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/widgets/page_shimmer.dart';
import '../application/bluetooth_printer_transport.dart';

class BluetoothPrinterPicker extends StatefulWidget {
  const BluetoothPrinterPicker({super.key, required this.transport});
  final BluetoothPrinterTransport transport;
  @override
  State<BluetoothPrinterPicker> createState() => _BluetoothPrinterPickerState();
}

class _BluetoothPrinterPickerState extends State<BluetoothPrinterPicker> {
  List<BluetoothPrinterDevice> devices = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.transport.pairedDevices();
      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (mounted) setState(() => devices = result);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('Printer Bluetooth')),
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    content: SizedBox(
      width: 420,
      height: 240,
      child: loading
          ? const PageShimmer()
          : error != null
          ? Center(child: Text(error!, textAlign: TextAlign.center))
          : devices.isEmpty
          ? const Center(
              child: Text(
                'Belum ada perangkat Bluetooth yang dipasangkan.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: Text(device.name),
                  subtitle: Text(device.address),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(device),
                );
              },
            ),
    ),
    actions: [
      if (error != null)
        TextButton.icon(
          onPressed: loading ? null : openAppSettings,
          icon: const Icon(Icons.admin_panel_settings_outlined),
          label: const Text('Izin Aplikasi'),
        ),
      TextButton.icon(
        onPressed: loading
            ? null
            : () async {
                try {
                  await widget.transport.openSettings();
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                }
              },
        icon: const Icon(Icons.settings_bluetooth),
        label: const Text('Pengaturan Bluetooth'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
    ],
  );
}
