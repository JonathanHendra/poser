import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/localization/app_language.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import 'app_router.dart';
import '../features/products/application/product_photo_picker.dart';
import '../features/cloud/application/cloud_sync.dart';

class PosUmkmApp extends ConsumerWidget {
  const PosUmkmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(recoveredProductPhotoProvider);
    ref.watch(cloudSyncProvider);
    return MaterialApp.router(
      title: 'POSPRO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider).mode,
      locale: ref.watch(appLanguageProvider).locale,
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final theme = Theme.of(context);
        final titleSize = MediaQuery.textScalerOf(context).scale(22);
        final toolbarHeight = (titleSize * 1.4 * (titleSize > 28 ? 2 : 1) + 16)
            .clamp(56.0, double.infinity)
            .toDouble();
        return Theme(
          data: theme.copyWith(
            appBarTheme: theme.appBarTheme.copyWith(
              toolbarHeight: toolbarHeight,
            ),
          ),
          child: child!,
        );
      },
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
