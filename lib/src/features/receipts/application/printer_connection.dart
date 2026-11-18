import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bluetooth_printer_transport.dart';
import '../presentation/bluetooth_printer_picker.dart';
import '../../auth/application/auth_controller.dart';

class PrinterConnection {
  PrinterConnection({
    BluetoothPrinterTransport? bluetooth,
    SharedPreferencesAsync? preferences,
    this.ownsSession,
  }) : bluetooth = bluetooth ?? createBluetoothPrinterTransport(),
       preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync preferences;
  final BluetoothPrinterTransport bluetooth;
  final bool Function(String)? ownsSession;
  String? _connectedAddress;
  Future<void> _queue = Future.value();
  void _checkOwner(String owner) {
    if (ownsSession != null && !ownsSession!(owner)) {
      throw StateError('Sesi berubah.');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  static bool isBluetooth(Printer printer) =>
      Uri.parse(printer.url).scheme == 'bluetooth';
  Future<void> _ensureConnected(String owner, String address) async {
    _checkOwner(owner);
    await bluetooth.checkReady();
    _checkOwner(owner);
    if (_connectedAddress == address && await bluetooth.connected) return;
    await bluetooth.disconnect();
    _connectedAddress = null;
    if (!await bluetooth.connect(address)) {
      throw StateError('Printer tidak dapat dihubungkan.');
    }
    _connectedAddress = address;
    _checkOwner(owner);
  }

  Future<void> selectBluetooth(String owner, BluetoothPrinterDevice device) =>
      _exclusive(() async {
        await _ensureConnected(owner, device.address);
        await preferences.setString(
          key(owner, 'url'),
          Uri(scheme: 'bluetooth', path: device.address).toString(),
        );
        await preferences.setString(key(owner, 'name'), device.name);
      });
  Future<bool> printBluetooth(String owner, List<int> bytes) =>
      _exclusive(() async {
        _checkOwner(owner);
        final printer = await selected(owner);
        if (printer == null || !isBluetooth(printer)) {
          throw StateError('Pilih printer Bluetooth terlebih dahulu.');
        }
        await _ensureConnected(owner, Uri.parse(printer.url).path);
        _checkOwner(owner);
        final sent = await bluetooth.write(bytes);
        if (!sent) {
          _connectedAddress = null;
          throw StateError(
            'Pengiriman struk gagal. Periksa printer sebelum mencetak ulang.',
          );
        }
        return true;
      });
  String key(String owner, String field) => 'pospro.printer.$owner.$field';
  Future<Printer?> selected(String owner) async {
    final url = await preferences.getString(key(owner, 'url'));
    if (url == null) return null;
    return Printer(
      url: url,
      name: await preferences.getString(key(owner, 'name')) ?? url,
    );
  }

  Future<Printer?> connect(BuildContext context, String owner) async {
    _checkOwner(owner);
    if (bluetooth.supported) {
      final device = await showDialog<BluetoothPrinterDevice>(
        context: context,
        builder: (_) => BluetoothPrinterPicker(transport: bluetooth),
      );
      if (device == null) return null;
      await selectBluetooth(owner, device);
      return selected(owner);
    }
    final info = await Printing.info();
    if (!info.canListPrinters && !info.directPrint) return null;
    if (!context.mounted) return null;
    final printer = await Printing.pickPrinter(
      context: context,
      title: 'Pilih printer',
    );
    if (printer == null) return null;
    _checkOwner(owner);
    await preferences.setString(key(owner, 'url'), printer.url);
    await preferences.setString(key(owner, 'name'), printer.name);
    return printer;
  }

  Future<void> disconnect(String owner) => _exclusive(() async {
    _checkOwner(owner);
    final printer = await selected(owner);
    if (printer != null && isBluetooth(printer)) {
      await bluetooth.disconnect();
      _connectedAddress = null;
    }
    await preferences.remove(key(owner, 'url'));
    await preferences.remove(key(owner, 'name'));
  });

  Future<bool> supportsSelection() async {
    if (bluetooth.supported) return true;
    final info = await Printing.info();
    return info.canListPrinters || info.directPrint;
  }
}

final printerConnectionProvider = Provider(
  (ref) => PrinterConnection(
    ownsSession: (owner) => ref.read(authProvider).user?.uid == owner,
  ),
);
