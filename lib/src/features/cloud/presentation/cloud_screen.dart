import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/cloud_sync.dart';
import '../data/drive_backup_api.dart';
import 'package:go_router/go_router.dart';

Future<void> syncCloud(BuildContext context, WidgetRef ref) async {
  final sync = ref.read(cloudSyncProvider);
  if (!sync.conflict) await sync.sync(interactive: true);
  if (!context.mounted || !sync.conflict) return;
  final choice = await showDialog<BackupChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pilih data untuk sinkronisasi'),
      content: const Text(
        'Data perangkat dan Google Drive berbeda. Gunakan data Drive untuk mengganti data lokal, atau simpan data perangkat untuk mengganti cadangan Drive. Perubahan pada versi yang diganti tidak digabungkan.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, BackupChoice.useDrive),
          child: const Text('Gunakan data Drive'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, BackupChoice.keepLocal),
          child: const Text('Simpan data perangkat'),
        ),
      ],
    ),
  );
  if (choice != null && context.mounted) {
    await sync.sync(interactive: true, choice: choice);
  }
}

class CloudSyncButton extends ConsumerWidget {
  const CloudSyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(cloudSyncProvider);
    return IconButton(
      tooltip: sync.busy
          ? 'Menyinkronkan Google Drive'
          : sync.isSynced
          ? 'Google Drive tersinkron'
          : 'Sinkronkan Google Drive',
      onPressed: sync.busy ? null : () => syncCloud(context, ref),
      icon: sync.busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              sync.isSynced
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_sync_outlined,
              color: sync.isSynced ? Colors.green : null,
            ),
    );
  }
}

class CloudStatus extends ConsumerWidget {
  const CloudStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(cloudSyncProvider);
    final synced = sync.isSynced;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            synced
                ? Icons.check_circle
                : sync.error != null
                ? Icons.cloud_off_outlined
                : Icons.cloud_outlined,
            color: synced ? Colors.green : null,
          ),
          title: const Text('Cadangan Google Drive'),
          subtitle: Text(
            sync.error ??
                (sync.permissionRequired
                    ? 'Izin Google Drive diperlukan'
                    : sync.busy
                    ? 'Menyinkronkan...'
                    : sync.backupFileId == null
                    ? 'Belum terhubung'
                    : sync.pending == 0
                    ? 'Tersinkron'
                    : '${sync.pending} perubahan menunggu'),
          ),
          trailing: IconButton(
            tooltip: sync.permissionRequired || sync.backupFileId == null
                ? 'Hubungkan Google Drive'
                : 'Sinkronkan sekarang',
            onPressed: sync.busy ? null : () => syncCloud(context, ref),
            icon: const Icon(Icons.sync),
          ),
        ),
        if (sync.busy) const LinearProgressIndicator(),
      ],
    );
  }
}

class CloudScreen extends ConsumerWidget {
  const CloudScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(cloudSyncProvider).backupFileId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive'),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/account'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CloudStatus(),
              if (id != null) ...[
                const SizedBox(height: 24),
                const Text(DriveBackupApi.filename),
                const SizedBox(height: 8),
                SelectableText('https://drive.google.com/file/d/$id/view'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
