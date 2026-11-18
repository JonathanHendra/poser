import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test/bluetooth_printer_test.dart' as tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tests.main();
  test(
    'Android PDF raster to ESC/POS prints both configured widths',
    tests.nativeRasterTest,
  );
}
