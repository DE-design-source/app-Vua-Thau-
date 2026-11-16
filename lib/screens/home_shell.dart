// 3 tab dưới đáy: Hồ sơ · Chụp hình (nút tròn vàng nổi ở giữa) · Bản đồ.
// Thu nhập và Tài khoản: 2 nút góc trên bên phải (TopActions), mở thành trang riêng.
// Tab chỉ dựng khi mở lần đầu, chọn lại là tải mới.
import 'package:flutter/material.dart';

import '../api.dart';
import '../page.dart';
import '../ui.dart';
import 'account.dart';
import 'houses.dart';
import 'income.dart';
import 'map.dart';
import 'submit.dart';

final tabIndex = ValueNotifier<int>(0);

const tabHouses = 0, tabShoot = 1, tabMap = 2;

void openIncome(BuildContext context) => push(context, const Scaffold(body: IncomeScreen()));
void openAccount(BuildContext context) => push(context, const Scaffold(body: AccountScreen()));

/// Góc trên bên phải các tab: Thu nhập, Tài khoản.
class TopActions extends StatelessWidget {
  const TopActions({super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Thu nhập',
          onPressed: () => openIncome(context),
          icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 24),
        ),
        IconButton(
          tooltip: 'Tài khoản',
          onPressed: () => openAccount(context),
          icon: const Icon(Icons.account_circle_outlined, color: Colors.white, size: 26),
        ),
      ]);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with RouteAware {
  final keys = List.generate(3, (_) => GlobalKey());
  final opened = <int>{};
  bool _sub = false;

  @override
  void initState() {
    super.initState();
    if (tabIndex.value > tabMap) tabIndex.value = tabHouses;
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

  // Quay về từ 1 hồ sơ, camera, Thu nhập...: tải lại tab đang mở
  @override
  void didPopNext() => _reload();

  void _go(int k) => tabIndex.value == k ? _reload() : tabIndex.value = k;

  Widget _tab(int i) {
    if (!opened.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      tabHouses => HousesScreen(key: keys[0]),
      tabShoot => SubmitScreen(key: keys[1]),
      _ => MapScreen(key: keys[2]),
    };
  }

  @override
  Widget build(BuildContext context) {
    final i = tabIndex.value;
    return Scaffold(
      body: IndexedStack(index: i, children: [for (var k = 0; k < 3; k++) _tab(k)]),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: badge,
        builder: (context, n, _) => Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 68,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _NavItem(
                    label: 'Hồ sơ',
                    icon: Icons.home_outlined,
                    iconOn: Icons.home,
                    on: i == tabHouses,
                    badge: n,
                    onTap: () => _go(tabHouses),
                  ),
                ),
                Expanded(child: _ShootItem(on: i == tabShoot, onTap: () => _go(tabShoot))),
                Expanded(
                  child: _NavItem(
                    label: 'Bản đồ',
                    icon: Icons.map_outlined,
                    iconOn: Icons.map,
                    on: i == tabMap,
                    onTap: () => _go(tabMap),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.icon, required this.iconOn, required this.on, required this.onTap, this.badge = 0});
  final String label;
  final IconData icon, iconOn;
  final bool on;
  final int badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 3, children: [
            // tab đang chọn: vạch vàng phía trên icon
            Container(width: 28, height: 3, color: on ? C.amber : Colors.transparent),
            Badge(
              isLabelVisible: badge > 0,
              backgroundColor: C.bad,
              label: Text(badge > 99 ? '99+' : '$badge'),
              child: Icon(on ? iconOn : icon, size: 24, color: on ? C.navy : C.subtle),
            ),
            Text(label,
                style: on
                    ? const TextStyle(color: C.navy, fontWeight: FontWeight.w600, fontSize: 12)
                    : const TextStyle(color: C.subtle, fontSize: 12)),
          ]),
        ),
      );
}

/// Nút giữa: tròn vàng nổi lên khỏi thanh tab.
class _ShootItem extends StatelessWidget {
  const _ShootItem({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: 'Chụp hình',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Nút tròn nhô lên trên mép thanh tab (không làm thanh cao thêm)
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            Positioned(
              top: -18,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: C.amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: const Icon(Icons.photo_camera, color: C.navy, size: 28),
              ),
            ),
            Positioned(
              bottom: 9,
              child: Text('Chụp hình',
                  style: TextStyle(color: C.navy, fontWeight: on ? FontWeight.w700 : FontWeight.w600, fontSize: 12)),
            ),
          ]),
        ),
      );
}
