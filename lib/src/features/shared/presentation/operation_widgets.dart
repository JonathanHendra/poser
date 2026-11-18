import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Text controllers must remain alive until the dialog's exit transition ends.
Future<T?> showOperationDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

Future<T?> showOperationSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext, ScrollController) builder,
}) async {
  TransitionRoute<dynamic>? route;
  final result = await showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    constraints: BoxConstraints.tightFor(
      width: MediaQuery.sizeOf(context).width,
    ),
    builder: (context) {
      route = ModalRoute.of(context) as TransitionRoute<dynamic>?;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          minChildSize: .3,
          maxChildSize: .95,
          snap: true,
          builder: (context, controller) => MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Builder(builder: (context) => builder(context, controller)),
          ),
        ),
      );
    },
  );
  await route?.completed;
  return result;
}

String rupiah(int value) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
).format(value);

String formatCurrency(int value, String currency) => NumberFormat.currency(
  locale: currency == 'IDR' ? 'id_ID' : 'en_US',
  symbol: currency == 'IDR' ? 'Rp ' : '$currency ',
  decimalDigits: 0,
).format(value);
Future<void> showFailure(BuildContext context, Object error) async {
  if (!context.mounted) return;
  final message = error is FormatException
      ? error.message
      : error is StateError
      ? error.message
      : error is ArgumentError
      ? '${error.message}'
      : 'Operasi belum berhasil. Periksa input dan coba lagi.';
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Belum berhasil'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  bool numeric = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showOperationDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
