import 'package:flutter/material.dart';
import '../localization/app_language.dart';
import '../theme/app_theme.dart';

class PosBottomNavigation extends StatelessWidget {
  const PosBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = ['Beranda', 'Produk', 'Kasir', 'Transaksi', 'Akun'];
    const icons = [
      Icons.home_outlined,
      Icons.inventory_2_outlined,
      Icons.point_of_sale,
      Icons.receipt_long_outlined,
      Icons.person_outline,
    ];
    final height = (60 + MediaQuery.textScalerOf(context).scale(12) * 1.4 * 2)
        .clamp(84.0, double.infinity)
        .toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final navigation = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        boxShadow: [
          BoxShadow(
            color: (dark ? AppColors.electricBlue : Colors.black).withValues(
              alpha: dark ? .24 : .20,
            ),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Material(
        color: scheme.surface,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          side: dark
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
        child: SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: SizedBox(
            height: height,
            child: Row(
              children: List.generate(5, (index) {
                final selected = index == selectedIndex;
                final cashier = index == 2;
                final color = selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant;
                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: tr(context, labels[index]),
                    child: Tooltip(
                      message: tr(context, labels[index]),
                      child: InkWell(
                        onTap: () => onSelected(index),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 8,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (cashier)
                                Transform.translate(
                                  offset: const Offset(0, -4),
                                  child: Material(
                                    color: AppColors.electricBlue,
                                    elevation: 2,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.input,
                                    ),
                                    child: const SizedBox(
                                      width: 48,
                                      height: 40,
                                      child: Icon(
                                        Icons.point_of_sale,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Icon(icons[index], color: color, size: 24),
                              const SizedBox(height: 4),
                              Flexible(
                                child: Text(
                                  tr(context, labels[index]),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: selected || cashier
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: cashier ? scheme.primary : color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
    return dark
        ? ClipRect(clipper: const _TopShadowClipper(), child: navigation)
        : navigation;
  }
}

class _TopShadowClipper extends CustomClipper<Rect> {
  const _TopShadowClipper();
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -32, size.width, size.height);
  @override
  bool shouldReclip(_TopShadowClipper oldClipper) => false;
}
