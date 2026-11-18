import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'bluetooth_printer_transport.dart';

BluetoothPrinterTransport createTransport() => _AndroidBluetoothTransport();

class _AndroidBluetoothTransport implements BluetoothPrinterTransport {
  @override
  bool get supported => Platform.isAndroid;
  @override
  Future<void> checkReady() async {
    if (!supported) {
      throw UnsupportedError(
        'Bluetooth printer hanya tersedia di aplikasi Android.',
      );
    }
    final permissions = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    if (permissions.values.any((permission) => !permission.isGranted)) {
      throw StateError('Izin perangkat sekitar/Bluetooth belum diberikan.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw StateError('Bluetooth belum aktif.');
    }
  }

  @override
  Future<List<BluetoothPrinterDevice>> pairedDevices() async {
    await checkReady();
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices
        .map(
          (device) => BluetoothPrinterDevice(
            name: device.name,
            address: device.macAdress,
          ),
        )
        .toList();
  }

  @override
  Future<bool> connect(String address) =>
      PrintBluetoothThermal.connect(macPrinterAddress: address);
  @override
  Future<bool> get connected => PrintBluetoothThermal.connectionStatus;
  @override
  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }

  @override
  Future<bool> write(List<int> bytes) =>
      PrintBluetoothThermal.writeBytes(bytes);
  @override
  Future<void> openSettings() => const MethodChannel(
    'pospro/bluetooth_settings',
  ).invokeMethod<void>('open');
}
