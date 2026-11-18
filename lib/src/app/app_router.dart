import 'package:flutter/material.dart';
import '../core/theme/brand_logo.dart';
import '../core/widgets/pos_bottom_navigation.dart';
import '../core/widgets/app_components.dart';
import '../core/localization/app_language.dart';
import 'startup_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/business/presentation/business_profile_screen.dart';
import '../features/catalog/presentation/catalog_product_screen.dart';
import '../features/cloud/presentation/cloud_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/purchases/presentation/purchase_screens.dart';
import '../features/receipts/presentation/receipt_screen.dart';
import '../features/receipts/presentation/payment_success_screen.dart';
import '../features/catalog/presentation/catalog_options_screen.dart';
import '../features/cash_flow/presentation/cash_flow_screen.dart';

import '../features/auth/presentation/auth_screens.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/pos/presentation/pos_screen.dart';
import '../features/products/presentation/products_screen.dart';
import '../features/shared/presentation/module_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authProvider);
  final startup = ref.read(startupProvider);
  final router = GoRouter(
    refreshListenable: Listenable.merge([auth, startup]),
    redirect: (context, state) {
      if (!startup.ready) return state.uri.path == '/splash' ? null : '/splash';
      return authRedirect(
        auth.phase,
        auth.onboarded,
        state.uri.path,
        introCompleted: startup.introCompleted,
      );
    },
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const GoogleSignInScreen(),
      ),
      GoRoute(
        path: '/auth/loading',
        builder: (context, state) => const AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/auth/error',
        builder: (context, state) => const AuthErrorScreen(),
      ),
      GoRoute(
        path: '/auth/session',
        builder: (context, state) => const SessionRestoreScreen(),
      ),
      GoRoute(
        path: '/cashier/success/:id',
        builder: (context, state) => PaymentSuccessScreen(
          saleId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/cashier',
            builder: (context, state) => const PosScreen(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsScreen(),
          ),
          GoRoute(
            path: '/products/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return id == null
                  ? const Scaffold(
                      body: Center(child: Text('Produk tidak ditemukan')),
                    )
                  : CatalogProductScreen(productId: id);
            },
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/transactions/:id',
            builder: (context, state) => ReceiptScreen(
              saleId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
            ),
          ),
          GoRoute(
            path: '/purchases/:id',
            builder: (context, state) => PurchaseDetailScreen(
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
            ),
          ),
          GoRoute(path: '/more', redirect: (context, state) => '/account'),
          GoRoute(
            path: '/account',
            builder: (context, state) => const AccountScreen(),
          ),
          GoRoute(
            path: '/module/:slug',
            builder: (context, state) => switch (state.pathParameters['slug']) {
              'google-drive' => const CloudScreen(),
              'cash-flow' || 'expenses' || 'income' => const CashFlowScreen(),
              'inventory' => const InventoryScreen(),
              'purchases' => const PurchasesScreen(),
              'suppliers' => const SuppliersScreen(),
              'printer' => const PrinterSettingsScreen(),
              'packages' => const PackagesScreen(),
              'business-settings' ||
              'store-settings' => const BusinessProfileScreen(),
              _ => ModuleScreen(slug: state.pathParameters['slug']!),
            },
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _navigation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _scrollingDown = false;
  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _navigation.stop();
      _navigation.value = 0;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (MediaQuery.sizeOf(context).width >= 720 ||
        widget.location == '/home' ||
        widget.location == '/module/store-settings' ||
        widget.location == '/module/business-settings' ||
        widget.location == '/module/printer' ||
        widget.location == '/module/cash-flow' ||
        widget.location == '/account' ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        !notification.metrics.outOfRange) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      _scrollingDown = delta > 0;
      _navigation.stop();
      final height =
          110 + MediaQuery.paddingOf(context).bottom.clamp(12, double.infinity);
      _navigation.value =
          notification.metrics.pixels <= notification.metrics.minScrollExtent
          ? 0
          : (_navigation.value + delta / height).clamp(0, 1);
    } else if (notification is ScrollEndNotification) {
      _navigation.animateTo(
        notification.metrics.pixels <= notification.metrics.minScrollExtent ||
                !_scrollingDown
            ? 0
            : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    return false;
  }

  @override
  void dispose() {
    _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.location.startsWith('/cashier')) return widget.child;
    final index = switch (widget.location) {
      String s when s.startsWith('/cashier') => 1,
      String s when s.startsWith('/products') => 2,
      String s when s.startsWith('/transactions') => 3,
      String s
          when s.startsWith('/account') ||
              s.startsWith('/more') ||
              s.startsWith('/module') =>
        4,
      _ => 0,
    };
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Builder(
          builder: (context) => MediaQuery.sizeOf(context).width >= 720
              ? Row(
                  children: [
                    NavigationRail(
                      extended: MediaQuery.sizeOf(context).width >= 1100,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: BrandLogo(
                          width: MediaQuery.sizeOf(context).width >= 1100
                              ? 140
                              : 64,
                        ),
                      ),
                      selectedIndex: index,
                      onDestinationSelected: (value) => context.go(
                        [
                          '/home',
                          '/cashier',
                          '/products',
                          '/transactions',
                          '/account',
                        ][value],
                      ),
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.home_outlined),
                          label: Text(tr(context, 'Beranda')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.point_of_sale),
                          label: Text(tr(context, 'Kasir')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text(tr(context, 'Produk')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: Text(tr(context, 'Transaksi')),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.person_outline),
                          label: Text(tr(context, 'Akun')),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: AppContent(child: widget.child)),
                  ],
                )
              : SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  child: widget.child,
                ),
        ),
      ),
      bottomNavigationBar:
          MediaQuery.sizeOf(context).width >= 720 ||
              MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : AnimatedBuilder(
              animation: _navigation,
              builder: (context, child) => _navigation.value == 0
                  ? child!
                  : ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: 1 - _navigation.value,
                        child: ExcludeFocus(
                          excluding: _navigation.value == 1,
                          child: ExcludeSemantics(
                            excluding: _navigation.value == 1,
                            child: IgnorePointer(
                              ignoring: _navigation.value == 1,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
              child: PosBottomNavigation(
                selectedIndex: switch (index) {
                  1 => 2,
                  2 => 1,
                  _ => index,
                },
                onSelected: (value) => context.go(
                  [
                    '/home',
                    '/products',
                    '/cashier',
                    '/transactions',
                    '/account',
                  ][value],
                ),
              ),
            ),
    );
  }
}
