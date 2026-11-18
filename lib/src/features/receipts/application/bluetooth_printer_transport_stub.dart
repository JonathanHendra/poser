import 'bluetooth_printer_transport.dart';

BluetoothPrinterTransport createTransport() => _UnsupportedTransport();

class _UnsupportedTransport implements BluetoothPrinterTransport {
  @override
  bool get supported => false;
  @override
  Future<void> checkReady() async => throw UnsupportedError(
    'Bluetooth printer hanya tersedia di aplikasi Android.',
  );
  @override
  Future<List<BluetoothPrinterDevice>> pairedDevices() async => [];
  @override
  Future<bool> connect(String address) async => false;
  @override
  Future<bool> get connected async => false;
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> write(List<int> bytes) async => false;
  @override
  Future<void> openSettings() async {}
}
