import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_components.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = const {
      'store-settings': 'Pengaturan Toko',
      'printer': 'Pengaturan Printer',
    };
    const icons = {
      'store-settings': Icons.storefront_outlined,
      'printer': Icons.print_outlined,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          children: modules.entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icons[entry.key]),
                      title: Text(entry.value),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/module/${entry.key}'),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
