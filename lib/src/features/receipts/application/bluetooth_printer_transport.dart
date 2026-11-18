import 'bluetooth_printer_transport_stub.dart'
    if (dart.library.io) 'bluetooth_printer_transport_native.dart'
    as platform;

class BluetoothPrinterDevice {
  const BluetoothPrinterDevice({required this.name, required this.address});
  final String name, address;
}

abstract interface class BluetoothPrinterTransport {
  bool get supported;
  Future<void> checkReady();
  Future<List<BluetoothPrinterDevice>> pairedDevices();
  Future<bool> connect(String address);
  Future<bool> get connected;
  Future<void> disconnect();
  Future<bool> write(List<int> bytes);
  Future<void> openSettings();
}

BluetoothPrinterTransport createBluetoothPrinterTransport() =>
    platform.createTransport();
