import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/theme/app_theme.dart';
import 'package:pos_umkm/src/features/shared/presentation/operation_widgets.dart';

void main() {
  for (final width in [390.0, 768.0]) {
    testWidgets('cashier sheet fills $width and cancels on downward drag', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result = 'pending';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showOperationSheet<String>(
                    context: context,
                    builder: (context, controller) => AlertDialog(
                      insetPadding: EdgeInsets.zero,
                      content: SizedBox(
                        width: width,
                        child: SingleChildScrollView(
                          controller: controller,
                          child: const SizedBox(
                            height: 1000,
                            child: Text('Isi produk'),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Pilih produk'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pilih produk'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(BottomSheet)).width, width);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 800),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  test('dark theme uses blue borders across standard surfaces', () {
    final theme = AppTheme.dark();
    expect(theme.colorScheme.outlineVariant, AppColors.electricBlue);
    expect(theme.colorScheme.outline, AppColors.blueAccent);
    final card = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(card.side.color, AppColors.electricBlue);
    final field =
        theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    expect(field.borderSide.color, AppColors.darkFieldBorder);
  });
}
