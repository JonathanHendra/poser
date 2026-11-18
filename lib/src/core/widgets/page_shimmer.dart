import 'package:flutter/material.dart';

class PageShimmer extends StatefulWidget {
  const PageShimmer({super.key});
  @override
  State<PageShimmer> createState() => _PageShimmerState();
}

class _PageShimmerState extends State<PageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
    } else if (!animation.isAnimating) {
      animation.repeat();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget block({double? width, double height = 14}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Semantics(
      label: 'Memuat halaman',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(-3 + animation.value * 6, 0),
              end: Alignment(-1 + animation.value * 6, 0),
              colors: [
                scheme.surfaceContainerHighest.withValues(alpha: 0),
                scheme.onSurface.withValues(alpha: .09),
                scheme.surfaceContainerHighest.withValues(alpha: 0),
              ],
            ).createShader(bounds),
            child: child,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(width: 170, height: 24),
                    const SizedBox(height: 24),
                    block(height: 46),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          Expanded(child: block(height: 82)),
                          if (i < 2) const SizedBox(width: 12),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          children: [
                            block(width: 54, height: 54),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  block(height: 16),
                                  const SizedBox(height: 10),
                                  FractionallySizedBox(
                                    widthFactor: .6,
                                    child: block(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
