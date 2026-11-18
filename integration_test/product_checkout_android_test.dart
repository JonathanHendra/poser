import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test/product_checkout_settings_test.dart' as settings;
import '../test/product_editor_repository_test.dart' as editor;
import '../test/product_unit_hierarchy_test.dart' as hierarchy;
import '../test/pos_widget_test.dart' as pos;
import '../test/product_form_settings_widget_test.dart' as form;
import '../test/product_variant_picker_test.dart' as picker;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Unit settings and variant surcharges', settings.main);
  group('Product editor', editor.main);
  group('Unit hierarchy', hierarchy.main);
  group('Cashier and cart', pos.main);
  group('Product form settings', form.main);
  group('Variant picker', picker.main);
}
