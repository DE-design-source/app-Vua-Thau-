// Bản free trong app (góp ý 23/11/2026): chưa đăng nhập vẫn xem được, giống web bản free (map.vuathau.com.vn/ban-do):
//   Bản đồ: công trình trên bản đồ, ghim 3 màu theo lần chụp gần nhất (vàng trong 30 ngày, xanh lá quá 30 ngày,
//     xanh dương từ 2 tháng); bấm ghim xem thẻ, mở chi tiết.
//   Công trình: danh sách thẻ ảnh mới nhất trước. Chi tiết: ảnh (đã che SĐT), giai đoạn, nhà thầu; không SĐT nhà thầu, không CTV.
//   Quy hoạch: mở trang Xem quy hoạch của web. Đăng nhập: CTV vào bằng SĐT (chưa có tài khoản thì đăng ký).
// Dữ liệu từ API công khai /public/map, /public/projects/{id}; ảnh qua link có chữ ký.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import '../api.dart';
import '../page.dart';
import '../ui.dart';
import 'login.dart';
import 'map.dart' show Pin, mapStyle;

const _vn = LatLng(16.0, 106.2);
const _yellow = Color(0xFFF5B301), _green = Color(0xFF22C55E), _blue = Color(0xFF1A56DB), _tag = Color(0xFF3B6FE0);

/// Số ngày từ lần chụp gần nhất tới hôm nay (giờ máy).
int _days(Json p) {
  final t = DateTime.tryParse(str(p['last_at']).isNotEmpty ? str(p['last_at']) : str(p['at']))?.toLocal();
  if (t == null) return 9999;
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).difference(DateTime(t.year, t.month, t.day)).inDays;
}

String _ago(int n) => n <= 0
    ? 'Hôm nay'
    : n == 1
        ? 'Hôm qua'
        : n < 30
            ? '$n ngày trước'
            : n < 365
                ? '${n ~/ 30} tháng trước'
                : '${n ~/ 365} năm trước';

Color _ageColor(int n, int stale) => n > stale * 2 ? _blue : n > stale ? _green : _yellow;

String _img(Object? url) => str(url).isEmpty ? '' : (str(url).startsWith('http') ? str(url) : '$host${str(url)}');

Future<void> openPlan() => launchUrl(Uri.parse('$host/quy-hoach'), mode: LaunchMode.inAppBrowserView);

void openLogin(BuildContext context) => push(context, const LoginScreen());

bool _fromLink = false; // link /app/?as=... chỉ mở màn đăng nhập 1 lần (đăng xuất rồi không mở lại)

// ---------------------------------------------------------------- khung tab

class GuestShell extends StatefulWidget {
  const GuestShell({super.key});
  @override
  State<GuestShell> createState() => _GuestShellState();
}

class _GuestShellState extends State<GuestShell> with PageData {
  @override
  String get path => '/public/map';
  @override
  bool get watchRoute => false;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      load();
      // trang đăng nhập web chuyển sang /app/?as=ctv|nhathau&phone=09...: mở sẵn vai trò + SĐT, tự đăng nhập
      if (!_fromLink) {
        _fromLink = true;
        final q = Uri.base.queryParameters;
        final role = q['as'] ?? '';
        if (role == roleCtv || role == roleNt) {
          push(context, LoginScreen(role: role, phone: q['phone'] ?? '', auto: (q['phone'] ?? '').isNotEmpty));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pts = ((d?['points'] as List?) ?? const []).cast<Json>();
    final stale = asInt(d?['stale_days']) > 0 ? asInt(d?['stale_days']) : 30;
    return Scaffold(
      backgroundColor: Colors.white,
      body: d == null
          ? SafeArea(child: Loading(err: err, retry: load))
          : IndexedStack(index: tab, children: [
              _GuestMap(points: pts, stale: stale),
              _GuestList(points: pts, stale: stale, reload: load),
            ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        backgroundColor: Colors.white,
        indicatorColor: C.amberBg,
        onDestinationSelected: (i) {
          if (i == 2) {
            openPlan();
          } else if (i == 3) {
            openLogin(context);
          } else {
            setState(() => tab = i);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Bản đồ'),
          NavigationDestination(icon: Icon(Icons.apartment_outlined), selectedIcon: Icon(Icons.apartment), label: 'Công trình'),
          NavigationDestination(icon: Icon(Icons.layers_outlined), label: 'Quy hoạch'),
          NavigationDestination(icon: Icon(Icons.login), label: 'Đăng nhập'),
        ],
      ),
    );
  }
}

/// Đầu trang: thương hiệu + nút Đăng nhập / Đăng ký CTV.
class _Head extends StatelessWidget {
  const _Head({required this.sub});
  final String sub;
  @override
  Widget build(BuildContext context) => Container(
        color: C.navy,
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 12, 12),
        child: Row(children: [
          const Brand(size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text.rich(TextSpan(text: 'Vua Thầu ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16), children: [
                TextSpan(text: 'Map', style: TextStyle(color: C.amber)),
              ])),
              Text(sub, style: const TextStyle(color: C.heroMuted, fontSize: 12)),
            ]),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.amber, foregroundColor: C.amberInk, visualDensity: VisualDensity.compact),
            onPressed: () => openLogin(context),
            child: const Text('Đăng nhập', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

// ---------------------------------------------------------------- bản đồ

class _GuestMap extends StatefulWidget {
  const _GuestMap({required this.points, required this.stale});
  final List<Json> points;
  final int stale;
  @override
  State<_GuestMap> createState() => _GuestMapState();
}

class _GuestMapState extends State<_GuestMap> {
  final ctl = MapController();

  void _card(Json p) {
    final n = _days(p);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            if (_img(p['cover_url']).isNotEmpty)
              ClipRRect(borderRadius: BorderRadius.circular(12), child: AspectRatio(aspectRatio: 16 / 9, child: Image.network(_img(p['cover_url']), fit: BoxFit.cover))),
            Text(str(p['address']).isNotEmpty ? str(p['address']) : 'Công trình', style: T.secT),
            Text([str(p['stage']), _ago(n), str(p['contractor'])].where((x) => x.isNotEmpty).join(' · '), style: T.muted),
            Btn('Xem chi tiết công trình', kind: BtnKind.primary, onPressed: () {
              Navigator.pop(ctx);
              push(context, GuestProject(id: asInt(p['id'])));
            }),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points.where((p) => p['lat'] != null && p['lng'] != null).toList();
    return Column(children: [
      _Head(sub: '${pts.length} công trình CTV đã chụp'),
      Expanded(
        child: Stack(children: [
          FlutterMap(
            mapController: ctl,
            options: MapOptions(
              initialCenter: _vn,
              initialZoom: 5.3,
              minZoom: 4,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () {
                if (pts.length > 1) {
                  ctl.fitCamera(CameraFit.coordinates(
                    coordinates: [for (final p in pts) LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())],
                    padding: const EdgeInsets.all(40),
                    maxZoom: 14,
                  ));
                }
              },
            ),
            children: [
              FutureBuilder<vmt.Style>(
                future: mapStyle,
                builder: (context, s) {
                  final st = s.data;
                  if (st != null) return vmt.VectorTileLayer(theme: st.theme, sprites: st.sprites, tileProviders: st.providers, maximumZoom: 19);
                  if (s.hasError) {
                    return TileLayer(urlTemplate: '$host/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'vn.com.vuathau', maxNativeZoom: 19);
                  }
                  return const SizedBox.shrink();
                },
              ),
              MarkerLayer(markers: [
                for (final p in pts)
                  Marker(
                    point: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
                    width: 26,
                    height: 35,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(onTap: () => _card(p), child: Pin(color: _ageColor(_days(p), widget.stale))),
                  ),
              ]),
            ],
          ),
          // chú thích 3 màu
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                for (final (c, t) in [(_yellow, 'Trong vòng ${widget.stale} ngày'), (_green, 'Quá ${widget.stale} ngày'), (_blue, 'Từ 2 tháng trước')])
                  Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                    SizedBox(width: 12, height: 16, child: Pin(color: c)),
                    Text(t, style: const TextStyle(fontSize: 11.5, color: C.text)),
                  ]),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- danh sách công trình

class _GuestList extends StatelessWidget {
  const _GuestList({required this.points, required this.stale, required this.reload});
  final List<Json> points;
  final int stale;
  final Future<void> Function() reload;
  @override
  Widget build(BuildContext context) {
    final rows = [...points]..sort((a, b) => _days(a).compareTo(_days(b)));
    return Column(children: [
      _Head(sub: '${rows.length} công trình, mới chụp trước'),
      Expanded(
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 18),
            itemBuilder: (context, i) => _Card(p: rows[i], stale: stale),
          ),
        ),
      ),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.p, required this.stale});
  final Json p;
  final int stale;
  @override
  Widget build(BuildContext context) {
    final n = _days(p);
    final parts = str(p['address']).split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final street = parts.isEmpty ? 'Công trình' : parts.length > 2 ? parts.sublist(0, parts.length - 2).join(', ') : parts.first;
    final area = parts.length > 2 ? parts.sublist(parts.length - 2).join(', ') : (parts.length == 2 ? parts.last : '');
    return InkWell(
      onTap: () => push(context, GuestProject(id: asInt(p['id']))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _img(p['cover_url']).isEmpty
                  ? Container(color: C.soft, child: const Icon(Icons.apartment, color: C.subtle, size: 40))
                  : Image.network(_img(p['cover_url']), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: C.soft)),
            ),
            Positioned(left: 10, top: 10, child: _chip(_ago(n), _tag, Colors.white)),
            if (str(p['stage']).isNotEmpty) Positioned(left: 10, bottom: 10, child: _chip(str(p['stage']), Colors.white, C.text)),
            Positioned(right: 10, top: 10, child: SizedBox(width: 18, height: 24, child: Pin(color: _ageColor(n, stale)))),
          ]),
        ),
        const SizedBox(height: 6),
        Text(street, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bold),
        if (area.isNotEmpty) Text(area, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.muted),
        if (str(p['contractor']).isNotEmpty) Text(str(p['contractor']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.text)),
      ]),
    );
  }
}

Widget _chip(String s, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7), boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 4)]),
      child: Text(s, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );

// ---------------------------------------------------------------- chi tiết công trình

class GuestProject extends StatefulWidget {
  const GuestProject({super.key, required this.id});
  final int id;
  @override
  State<GuestProject> createState() => _GuestProjectState();
}

class _GuestProjectState extends State<GuestProject> with PageData {
  @override
  String get path => '/public/projects/${widget.id}';

  Widget _fact(String label, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: T.muted)),
          Expanded(child: Text(v.isEmpty ? '—' : v, style: T.body)),
        ]),
      );

  void _view(List<Json> ps, int start) => push(
        context,
        Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: PageView(
            controller: PageController(initialPage: start),
            children: [for (final x in ps) InteractiveViewer(child: Center(child: Image.network(_img(x['url']), fit: BoxFit.contain)))],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = d;
    final ps = ((p?['photos'] as List?) ?? const []).cast<Json>();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Chi tiết công trình'), backgroundColor: Colors.white, surfaceTintColor: Colors.white),
      body: p == null
          ? Loading(err: err, retry: load)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              Text(str(p['address']).isNotEmpty ? str(p['address']) : 'Công trình', style: T.secT),
              const SizedBox(height: 4),
              Text([str(p['province_name']), str(p['stage']), 'chụp ${_ago(_days({'at': p['at']})).toLowerCase()}'].where((x) => x.isNotEmpty).join(' · '),
                  style: T.muted),
              const SizedBox(height: 14),
              if (ps.isEmpty) const Text('Chưa có ảnh.', style: T.muted),
              if (ps.isNotEmpty)
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 3 / 4,
                  children: [
                    for (var i = 0; i < ps.length; i++)
                      GestureDetector(
                        onTap: () => _view(ps, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(_img(ps[i]['url']), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: C.soft)),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              const Text('Thông tin công trình', style: T.bold),
              _fact('Địa chỉ', str(p['address'])),
              _fact('Tỉnh, thành', str(p['province_name'])),
              _fact('Giai đoạn', str(p['stage'])),
              _fact('Số tầng', p['floors'] == null ? '' : str(p['floors'])),
              _fact('Nhà thầu', str(p['contractor'])),
              const SizedBox(height: 12),
              if (p['lat'] != null)
                Btn('Xem trên Google Maps', onPressed: () {
                  launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${p['lat']},${p['lng']}'), mode: LaunchMode.externalApplication);
                }),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: C.amberBg, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                  const Text('Xem SĐT nhà thầu, chụp công trình nhận tiền: đăng nhập bằng số điện thoại.', style: T.body),
                  Btn('Đăng nhập / Đăng ký CTV', kind: BtnKind.primary, onPressed: () => openLogin(context)),
                ]),
              ),
            ]),
    );
  }
}
