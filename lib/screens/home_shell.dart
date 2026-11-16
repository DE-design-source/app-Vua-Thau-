// 4 tab dưới đáy: Hồ sơ, Nộp ảnh, Thu nhập, Tài khoản. Tab chỉ dựng khi mở lần đầu, chọn lại là tải mới.
import 'package:flutter/material.dart';

import '../api.dart';
import '../page.dart';
import '../ui.dart';
import 'account.dart';
import 'houses.dart';
import 'income.dart';
import 'submit.dart';

final tabIndex = ValueNotifier<int>(0);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with RouteAware {
  final keys = List.generate(4, (_) => GlobalKey());
  final opened = <int>{};
  bool _sub = false;

  @override
  void initState() {
    super.initState();
    opened.add(tabIndex.value);
    tabIndex.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ModalRoute.of(context);
    if (!_sub && r != null) {
      routeObserver.subscribe(this, r);
      _sub = true;
    }
  }

  @override
  void dispose() {
    tabIndex.removeListener(_changed);
    if (_sub) routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _reload() => (keys[tabIndex.value].currentState as Reloadable?)?.load();

  void _changed() {
    final i = tabIndex.value;
    if (opened.add(i)) {
      setState(() {}); // dựng lần đầu: tự tải trong initState
    } else {
      setState(() {});
      _reload();
    }
  }

  // Quay về từ 1 hồ sơ, camera...: tải lại tab đang mở
  @override
  void didPopNext() => _reload();

  Widget _tab(int i) {
    if (!opened.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      0 => HousesScreen(key: keys[0]),
      1 => SubmitScreen(key: keys[1]),
      2 => IncomeScreen(key: keys[2]),
      _ => AccountScreen(key: keys[3]),
    };
  }

  @override
  Widget build(BuildContext context) {
    final i = tabIndex.value;
    return Scaffold(
      body: IndexedStack(index: i, children: [for (var k = 0; k < 4; k++) _tab(k)]),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: badge,
        builder: (context, n, _) => NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
                ? const TextStyle(color: C.navy, fontWeight: FontWeight.w700, fontSize: 12)
                : const TextStyle(color: C.muted, fontSize: 12)),
            iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.navy : C.muted)),
          ),
          child: NavigationBar(
            selectedIndex: i,
            backgroundColor: Colors.white,
            indicatorColor: C.amberBg,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (k) => tabIndex.value == k ? _reload() : tabIndex.value = k,
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: n > 0,
                  backgroundColor: const Color(0xFFE5484D),
                  label: Text(n > 99 ? '99+' : '$n'),
                  child: const Icon(Icons.home_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: n > 0,
                  backgroundColor: const Color(0xFFE5484D),
                  label: Text(n > 99 ? '99+' : '$n'),
                  child: const Icon(Icons.home),
                ),
                label: 'Hồ sơ',
              ),
              const NavigationDestination(icon: Icon(Icons.add_a_photo_outlined), selectedIcon: Icon(Icons.add_a_photo), label: 'Nộp ảnh'),
              const NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Thu nhập'),
              const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Tài khoản'),
            ],
          ),
        ),
      ),
    );
  }
}
