import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class StoreSaveProgress extends StatefulWidget {
  const StoreSaveProgress({super.key, required this.syncing});
  final ValueListenable<bool> syncing;

  @override
  State<StoreSaveProgress> createState() => _StoreSaveProgressState();
}

class _StoreSaveProgressState extends State<StoreSaveProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
      animation.value = 0;
    } else {
      animation.repeat();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.syncing,
        builder: (context, syncing, _) {
          final title = syncing
              ? 'Menyinkronkan Google Drive'
              : 'Menyimpan informasi toko';
          final reducedMotion = MediaQuery.disableAnimationsOf(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: title,
                liveRegion: true,
                child: SizedBox(
                  width: 112,
                  height: 112,
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) => Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(
                          angle: animation.value * math.pi * 2,
                          child: const SizedBox.square(
                            dimension: 106,
                            child: CircularProgressIndicator(
                              value: 0.72,
                              strokeWidth: 3,
                              color: AppColors.electricBlue,
                            ),
                          ),
                        ),
                        Transform.rotate(
                          angle: -animation.value * math.pi * 2,
                          child: const SizedBox.square(
                            dimension: 86,
                            child: CircularProgressIndicator(
                              value: 0.28,
                              strokeWidth: 2,
                              color: Color(0xFF16B8A6),
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale:
                              1 +
                              math.sin(animation.value * math.pi * 2) * 0.05,
                          child: AnimatedSwitcher(
                            duration: reducedMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 300),
                            child: Icon(
                              syncing
                                  ? Icons.cloud_upload_outlined
                                  : Icons.storefront_outlined,
                              key: ValueKey(syncing),
                              color: AppColors.electricBlue,
                              size: 38,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                syncing
                    ? 'Memperbarui database dan cadangan toko...'
                    : 'Menyimpan perubahan toko Anda...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
