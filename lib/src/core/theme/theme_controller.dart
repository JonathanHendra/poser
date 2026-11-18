import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = ChangeNotifierProvider<ThemeController>(
  (ref) => ThemeController(),
);

class ThemeController extends ChangeNotifier {
  ThemeController() {
    unawaited(_load());
  }
  final _preferences = SharedPreferencesAsync();
  ThemeMode mode = ThemeMode.system;
  bool _changed = false, _disposed = false;
  Future<void> _load() async {
    try {
      final value = await _preferences.getString('pospro.theme');
      if (_disposed || _changed) return;
      mode =
          ThemeMode.values.where((m) => m.name == value).firstOrNull ??
          ThemeMode.system;
      notifyListeners();
    } catch (_) {
      /* Keep the system theme when preferences are unavailable. */
    }
  }

  Future<void> setMode(ThemeMode value) async {
    _changed = true;
    mode = value;
    notifyListeners();
    try {
      await _preferences.setString('pospro.theme', value.name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(themeModeProvider);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Tema tampilan',
      initialValue: controller.mode,
      onSelected: controller.setMode,
      icon: Icon(
        Theme.of(context).brightness == Brightness.dark
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined,
      ),
      itemBuilder: (_) => [
        for (final entry in const [
          (ThemeMode.light, Icons.light_mode_outlined, 'Terang'),
          (ThemeMode.dark, Icons.dark_mode_outlined, 'Gelap'),
          (ThemeMode.system, Icons.brightness_auto_outlined, 'Sistem'),
        ])
          PopupMenuItem(
            value: entry.$1,
            child: Row(
              children: [
                Icon(entry.$2),
                const SizedBox(width: 12),
                Expanded(child: Text(entry.$3)),
                if (controller.mode == entry.$1)
                  const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class ThemeModeSwitch extends ConsumerWidget {
  const ThemeModeSwitch({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: dark ? 'Tema gelap' : 'Tema terang',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            size: 20,
          ),
          Switch(
            value: dark,
            thumbIcon: WidgetStateProperty.resolveWith(
              (states) => Icon(
                states.contains(WidgetState.selected)
                    ? Icons.dark_mode
                    : Icons.light_mode,
                size: 16,
              ),
            ),
            onChanged: (value) => ref
                .read(themeModeProvider)
                .setMode(value ? ThemeMode.dark : ThemeMode.light),
          ),
        ],
      ),
    );
  }
}

class ThemeModeToggle extends ConsumerWidget {
  const ThemeModeToggle({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Gunakan tema terang' : 'Gunakan tema gelap',
      icon: Icon(dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
      onPressed: () => ref
          .read(themeModeProvider)
          .setMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
