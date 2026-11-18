import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:pos_umkm/src/features/receipts/application/bluetooth_printer_transport.dart';
import 'package:pos_umkm/src/features/receipts/application/printer_connection.dart';
import 'package:pos_umkm/src/features/receipts/application/printer_service.dart';
import 'package:pos_umkm/src/features/receipts/application/thermal_receipt_encoder.dart';
import 'package:pos_umkm/src/features/receipts/presentation/bluetooth_printer_picker.dart';
import 'package:flutter/material.dart';

class FakeBluetoothPrinter implements BluetoothPrinterTransport {
  bool available = true, online = false, canConnect = true, canWrite = true;
  int connections = 0;
  final writes = <List<int>>[];
  @override
  bool get supported => true;
  @override
  Future<void> checkReady() async {
    if (!available) throw StateError('Bluetooth belum aktif.');
  }

  @override
  Future<List<BluetoothPrinterDevice>> pairedDevices() async => [device];
  @override
  Future<bool> connect(String address) async {
    connections++;
    online = canConnect;
    return online;
  }

  @override
  Future<bool> get connected async => online;
  @override
  Future<void> disconnect() async {
    online = false;
  }

  @override
  Future<bool> write(List<int> bytes) async {
    writes.add(List.of(bytes));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return canWrite;
  }

  @override
  Future<void> openSettings() async {}
}

const device = BluetoothPrinterDevice(
  name: 'Printer Thermal',
  address: 'AA:BB:CC:DD:EE:FF',
);
bool containsBytes(List<int> bytes, List<int> pattern) {
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    if (List.generate(
      pattern.length,
      (j) => bytes[i + j] == pattern[j],
    ).every((v) => v)) {
      return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  test(
    'selection persists by owner and reconnects after restart without duplicate writes',
    () async {
      final transport = FakeBluetoothPrinter();
      final connection = PrinterConnection(bluetooth: transport);
      await connection.selectBluetooth('a', device);
      expect(await connection.selected('b'), isNull);
      expect(
        Uri.parse((await connection.selected('a'))!.url).path,
        device.address,
      );
      final reopened = PrinterConnection(bluetooth: transport);
      await reopened.printBluetooth('a', [1, 2, 3]);
      expect(transport.connections, 2);
      expect(transport.writes, [
        [1, 2, 3],
      ]);
      await reopened.disconnect('a');
      expect(await reopened.selected('a'), isNull);
      expect(transport.online, isFalse);
    },
  );
  test(
    'failed selection preserves old printer; failed send is never retried automatically',
    () async {
      final transport = FakeBluetoothPrinter();
      final connection = PrinterConnection(bluetooth: transport);
      await connection.selectBluetooth('a', device);
      transport.canConnect = false;
      await expectLater(
        connection.selectBluetooth(
          'a',
          const BluetoothPrinterDevice(
            name: 'Wrong',
            address: '00:11:22:33:44:55',
          ),
        ),
        throwsStateError,
      );
      expect((await connection.selected('a'))!.name, device.name);
      transport.canConnect = true;
      transport.canWrite = false;
      await expectLater(
        connection.printBluetooth('a', [7, 8]),
        throwsStateError,
      );
      expect(transport.writes, [
        [7, 8],
      ]);
      transport.canWrite = true;
      await connection.printBluetooth('a', [9]);
      expect(transport.writes, [
        [7, 8],
        [9],
      ]);
    },
  );
  test('concurrent jobs serialize and changed sessions cannot send', () async {
    var owner = 'a';
    final transport = FakeBluetoothPrinter();
    final connection = PrinterConnection(
      bluetooth: transport,
      ownsSession: (uid) => owner == uid,
    );
    await connection.selectBluetooth('a', device);
    await Future.wait([
      connection.printBluetooth('a', [1]),
      connection.printBluetooth('a', [2]),
    ]);
    expect(transport.writes, [
      [1],
      [2],
    ]);
    owner = 'b';
    await expectLater(connection.printBluetooth('a', [3]), throwsStateError);
    expect(transport.writes.length, 2);
  });
  test(
    '58/80 raster widths follow receipt settings and trailing white paper is trimmed',
    () async {
      final page = img.Image(width: 384, height: 300);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(
        page,
        x1: 20,
        y1: 5,
        x2: 80,
        y2: 24,
        color: img.ColorRgb8(0, 0, 0),
      );
      final png = Uint8List.fromList(img.encodePng(page));
      for (final width in [58, 80]) {
        final bytes = await encodeThermalPages(
          Stream.value(png),
          paperWidth: width,
        );
        expect(
          containsBytes(bytes, [29, 118, 48, 0, width == 58 ? 48 : 72, 0]),
          isTrue,
        );
        expect(bytes.length, lessThan(48 * 300));
      }
      await expectLater(
        encodeThermalPages(Stream.value(png), paperWidth: 57),
        throwsArgumentError,
      );
    },
  );
  testWidgets('paired printer picker supports light/dark and small screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: BluetoothPrinterPicker(transport: FakeBluetoothPrinter()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(device.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> nativeRasterTest() async {
  final transport = FakeBluetoothPrinter();
  final connection = PrinterConnection(bluetooth: transport);
  await connection.selectBluetooth('a', device);
  final service = SystemPrinterService(connection: connection, owner: 'a');
  const receipt = ReceiptData(
    id: 1,
    identity: {
      'name': 'Toko Uji',
      'store': 'Toko Uji',
      'currency': 'IDR',
      'footer': 'Terima kasih',
    },
    lines: [
      {
        'name': 'Donat Coklat',
        'unit': 'pcs',
        'quantity': '2',
        'price': 5000,
        'total': 10000,
        'discount': 0,
        'modifiers': [],
      },
    ],
    payments: [
      {'method': 'cash', 'tendered': 20000, 'status': 'recorded'},
    ],
    subtotal: 10000,
    discount: 0,
    tax: 0,
    total: 10000,
    change: 10000,
    timestamp: 1791817200000,
    status: 'completed',
  );
  for (final width in [58, 80]) {
    expect(await service.printReceipt(receipt, paperWidth: width), isTrue);
    expect(
      containsBytes(transport.writes.last, [
        29,
        118,
        48,
        0,
        width == 58 ? 48 : 72,
        0,
      ]),
      isTrue,
    );
  }
}
