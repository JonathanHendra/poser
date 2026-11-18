import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../pos/application/cashier_catalog.dart';
import '../../pos/application/pos_controller.dart';
import '../../shared/presentation/operation_widgets.dart';
import '../../shared/presentation/product_picker.dart';

Future<void> addProductToCashier(
  BuildContext context,
  WidgetRef ref,
  String owner,
  int id,
) async {
  try {
    final cart = ref.read(posControllerProvider(owner));
    if (cart.busy) return;
    final products = await ref.read(
      cashierCatalogProvider((owner, cart.storeId)).future,
    );
    final product = products.firstWhere((entry) => entry.product.id == id);
    if (!context.mounted ||
        !product.available ||
        ref.read(authProvider).user?.uid != owner) {
      return;
    }
    final selection = await configureLine(
      context,
      ref,
      owner,
      id,
      unitId: product.sellingUnitId,
    );
    if (selection != null &&
        context.mounted &&
        ref.read(authProvider).user?.uid == owner) {
      cart.addAll(selection.lines);
      context.go('/cashier');
    }
  } catch (error) {
    if (context.mounted) await showFailure(context, error);
  }
}
