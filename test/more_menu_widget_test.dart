import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_umkm/src/core/theme/app_theme.dart';
import 'package:pos_umkm/src/features/more/presentation/more_screen.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('more menu keeps only store and printer settings dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: const MoreScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pengaturan Toko'), findsOneWidget);
      expect(find.text('Pengaturan Printer'), findsOneWidget);
      for (final label in [
        'Pengeluaran',
        'Backup dan Restore',
        'Google Drive',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
