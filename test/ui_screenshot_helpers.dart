import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadUiFonts() async {
  await (FontLoader('POSPRO Sans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<void> captureUi(GlobalKey key, String name, WidgetTester tester) async {
  if (!const bool.fromEnvironment('POSPRO_UI_SCREENSHOTS')) return;
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = '${Directory.systemTemp.path}/pospro-$name.png';
      await File(path).writeAsBytes(data!.buffer.asUint8List());
      debugPrint('POSPRO_UI_SCREENSHOT: $path');
    } finally {
      image.dispose();
    }
  });
}
