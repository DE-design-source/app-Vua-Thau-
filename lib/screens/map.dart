// Bản đồ (tab cuối): công trình của mình (màu theo trạng thái, bấm để mở hồ sơ) + chấm công trình CTV khác (chỉ vị trí):
// vàng nhạt = chụp chưa quá hạn chặn trùng, xanh lá = cần cập nhật. Ô tìm địa điểm: đếm công trình trong bán kính. Nền OSM qua /tiles.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import '../api.dart';
import '../page.dart';
import '../toast.dart';
import '../ui.dart';
import 'home_shell.dart' show TopActions;
import 'house.dart';

const _vn = LatLng(16.0, 106.2);

// Nền bản đồ kiểu Airbnb: cùng file kiểu với web (máy chủ phục vụ /map-style.json, vector OpenFreeMap tô lại màu).
// Đọc 1 lần cho cả phiên. Lỗi (mất mạng, máy chủ cũ): dùng nền OSM qua /tiles.
final Future<vmt.Style> _mapStyle = vmt.StyleReader(uri: '$host/map-style.json').read();

// Công trình theo lần chụp: chưa quá số ngày chặn trùng vàng nhạt, quá thì xanh lá (cần cập nhật, được chụp lại)
// vàng: chụp chưa quá hạn (giống web); xanh lá tươi: cần cập nhật
const ageFresh = Color(0xFFF5B301), ageFreshLine = Color(0xFFB7791F), ageStale = Color(0xFF22C55E);
const minePin = C.wait; // công trình của mình: ghim xanh dương
const _radii = [500, 1000, 2000, 5000];

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with PageData {
  @override
  String get path => '/ctv/map';
  @override
  bool get watchRoute => false; // trong tab: thanh tab tự gọi load()

  final ctl = MapController();
  bool ready = false, fitted = false, locating = false;
  LatLng? me;

  // Ô tìm địa điểm
  final q = TextEditingController();
  List<Json>? hits;
  Json? place;
  int radius = 1000;
  bool finding = false;

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> find() async {
    final s = q.text.trim();
    if (s.length < 3) return;
    FocusScope.of(context).unfocus();
    setState(() => finding = true);
    try {
      final j = await api('/geo/search?q=${Uri.encodeQueryComponent(s)}');
      final ps = ((j['places'] as List?) ?? const []).cast<Json>();
      if (!mounted) return;
      setState(() {
        hits = ps;
        place = null;
      });
      if (ps.length == 1) pick(ps.first);
      if (ps.isEmpty) toast('Không thấy địa điểm này. Ghi rõ hơn: số nhà, tên đường, phường, tỉnh.');
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => finding = false);
    }
  }

  void pick(Json p) {
    setState(() => place = p);
    _zoomTo(p);
  }

  void _zoomTo(Json p) {
    final c = LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    // vòng bán kính vừa màn hình
    const d = Distance();
    ctl.fitCamera(CameraFit.coordinates(
        coordinates: [d.offset(c, radius.toDouble(), 0), d.offset(c, radius.toDouble(), 180), d.offset(c, radius.toDouble(), 90), d.offset(c, radius.toDouble(), 270)],
        padding: const EdgeInsets.all(24)));
  }

  /// Số công trình trong vòng: [tổng, cần cập nhật]
  (int, int) _count() {
    final p = place;
    if (p == null) return (0, 0);
    final c = LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    const d = Distance();
    var n = 0, stale = 0;
    for (final o in [...mine, ...others]) {
      if (d(c, LatLng((o['lat'] as num).toDouble(), (o['lng'] as num).toDouble())) <= radius) {
        n++;
        if (o.containsKey('recent') && o['recent'] != true) stale++;
      }
    }
    return (n, stale);
  }

  List<Json> get mine => ((d?['mine'] as List?) ?? const []).cast<Json>();
  List<Json> get others => ((d?['others'] as List?) ?? const []).cast<Json>();

  // Lọc công trình: all = tất cả, mine = của bạn, fresh = cập nhật chưa quá hạn, stale = quá hạn cần cập nhật
  String filter = 'all';
  bool filterOpen = false;
  bool _keep(Json o) => switch (filter) { 'fresh' => o['recent'] == true, 'stale' => o['recent'] != true, _ => true };
  List<Json> get shownMine => [for (final p in mine) if (_keep(p)) p];
  List<Json> get shownOthers => filter == 'mine' ? const [] : [for (final o in others) if (_keep(o)) o];
  int _n(bool recent) => [...mine, ...others].where((o) => (o['recent'] == true) == recent).length;

  @override
  void onData(Json j) => _fit();

  // Lần đầu: canh vừa công trình của mình; chưa có thì cả nước
  void _fit() {
    if (!ready || fitted || d == null) return;
    fitted = true;
    final pts = [for (final p in mine) LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())];
    if (pts.length == 1) {
      ctl.move(pts.first, 15);
    } else if (pts.length > 1) {
      ctl.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48), maxZoom: 15));
    }
  }

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        toast('Chưa cho phép Vị trí');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 15));
      final here = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => me = here);
      ctl.move(here, 16);
    } catch (_) {
      toast('Không lấy được vị trí, bật GPS rồi thử lại');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void open(Json p) {
    final lat = p['lat'], lng = p['lng'];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Row(spacing: 8, children: [
              Text(hsId(p['id']), style: T.mono),
              Pill(cfg.statusLabel(str(p['status'])), tone: cfg.statusTone(str(p['status']))),
              const Spacer(),
              Text(str(p['at']), style: T.mono),
            ]),
            Text(str(p['address']).isNotEmpty ? str(p['address']) : '(chưa có địa chỉ)', style: T.bold),
            Row(spacing: 10, children: [
              Expanded(
                child: Btn('Mở hồ sơ', kind: BtnKind.primary, onPressed: () {
                  Navigator.of(ctx).pop();
                  push(context, HouseScreen(id: asInt(p['id'])));
                }),
              ),
              Expanded(
                child: Btn('Google Maps',
                    onPressed: () => launchUrl(Uri.parse(gmapUrl(lat, lng)), mode: LaunchMode.externalApplication)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final dup = asInt(d?['dup_days']);
    return Column(children: [
      const VtAppBar(title: 'Bản đồ công trình', sub: 'Của bạn và nơi đã có người chụp', right: TopActions()),
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
                ready = true;
                _fit();
              },
            ),
            children: [
              FutureBuilder<vmt.Style>(
                future: _mapStyle,
                builder: (context, s) {
                  final st = s.data;
                  if (st != null) {
                    return vmt.VectorTileLayer(theme: st.theme, sprites: st.sprites, tileProviders: st.providers, maximumZoom: 19);
                  }
                  if (s.hasError) {
                    return TileLayer(
                      urlTemplate: '$host/tiles/{z}/{x}/{y}.png',
                      userAgentPackageName: 'vn.com.vuathau',
                      maxNativeZoom: 19,
                      retinaMode: RetinaMode.isHighDensity(context),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              // Vòng tìm địa điểm
              if (place != null)
                CircleLayer(circles: [
                  CircleMarker(
                    point: LatLng((place!['lat'] as num).toDouble(), (place!['lng'] as num).toDouble()),
                    radius: radius.toDouble(),
                    useRadiusInMeter: true,
                    color: C.wait.withValues(alpha: .07),
                    borderColor: C.wait,
                    borderStrokeWidth: 2,
                  ),
                ]),
              // Công trình CTV khác: ghim nhỏ (không chi tiết). Vàng: chụp chưa quá hạn (chụp lại sẽ bị chặn trùng);
              // xanh lá: quá hạn, cần cập nhật công trình (được chụp lại)
              MarkerLayer(markers: [
                for (final o in shownOthers)
                  Marker(
                    point: LatLng((o['lat'] as num).toDouble(), (o['lng'] as num).toDouble()),
                    width: 22,
                    height: 29,
                    alignment: Alignment.topCenter,
                    child: Pin(color: o['recent'] == true ? ageFresh : ageStale),
                  ),
              ]),
              MarkerLayer(markers: [
                for (final p in shownMine)
                  Marker(
                    point: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
                    width: 30,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      button: true,
                      label: 'Hồ sơ ${hsId(p['id'])}',
                      child: GestureDetector(onTap: () => open(p), child: const Pin(color: minePin)),
                    ),
                  ),
                if (me != null)
                  Marker(
                    point: me!,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: C.wait,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
                      ),
                    ),
                  ),
              ]),
              // Ghi nguồn bản đồ (gọn, không tràn trên máy màn hẹp)
              const Align(
                alignment: Alignment.bottomRight,
                child: ColoredBox(
                  color: Color(0xCCFFFFFF),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10.5, color: C.muted)),
                  ),
                ),
              ),
            ],
          ),
          // Lọc công trình (kiêm chú thích màu)
          Positioned(left: 10, right: 64, bottom: 24, child: Align(alignment: Alignment.bottomLeft, child: _filterBox(dup > 0 ? dup : 30))),
          // Ô tìm địa điểm + kết quả + số công trình trong vòng
          Positioned(left: 10, right: 10, top: 10, child: _searchBox()),
          if (busy && d == null) const Center(child: CircularProgressIndicator()),
          if (err.isNotEmpty && d == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
                  Text(err, textAlign: TextAlign.center, style: T.body),
                  Btn('Thử lại', onPressed: load),
                ]),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 24,
            child: FloatingActionButton.small(
              heroTag: 'vitri',
              tooltip: 'Vị trí của tôi',
              backgroundColor: Colors.white,
              foregroundColor: C.navy,
              elevation: 2,
              onPressed: locating ? null : locate,
              child: locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _searchBox() {
    final (n, stale) = _count();
    final box = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(R.card),
      border: Border.all(color: C.line),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Container(
        decoration: box,
        child: Row(children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, color: C.subtle, size: 20),
          Expanded(
            child: TextField(
              controller: q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => find(),
              decoration: const InputDecoration(
                  hintText: 'Tìm địa điểm: số nhà, đường, phường…', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
            ),
          ),
          if (finding)
            const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else if (hits != null || place != null)
            IconButton(
              tooltip: 'Xoá tìm kiếm',
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => setState(() {
                q.clear();
                hits = null;
                place = null;
              }),
            )
          else
            IconButton(tooltip: 'Tìm', icon: const Icon(Icons.arrow_forward, size: 20), onPressed: find),
        ]),
      ),
      if (hits != null && hits!.length > 1 && place == null)
        Container(
          decoration: box,
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
            for (final h in hits!)
              ListTile(dense: true, title: Text(str(h['name']), maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => pick(h)),
          ]),
        ),
      if (place != null)
        Container(
          decoration: box,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text(str(place!['name']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
              const Text('Trong bán kính', style: TextStyle(fontSize: 13.5)),
              DropdownButton<int>(
                value: radius,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [for (final r in _radii) DropdownMenuItem(value: r, child: Text(r >= 1000 ? '${r ~/ 1000} km' : '$r m'))],
                onChanged: (r) {
                  if (r == null) return;
                  setState(() => radius = r);
                  _zoomTo(place!);
                },
              ),
              Text.rich(TextSpan(style: const TextStyle(fontSize: 13.5), children: [
                const TextSpan(text: ': '),
                TextSpan(text: '$n', style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' công trình'),
                if (stale > 0) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(text: '$stale', style: const TextStyle(fontWeight: FontWeight.w700, color: ageStale)),
                  const TextSpan(text: ' cần cập nhật'),
                ],
              ])),
            ]),
            if (hits != null && hits!.length > 1)
              GestureDetector(
                onTap: () => setState(() => place = null),
                child: Text('Chọn kết quả khác (${hits!.length})', style: const TextStyle(color: C.navy3, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
    ]);
  }

  Widget _filterBox(int days) {
    // màu null: không có chấm (Xem tất cả)
    final opts = <(String, String, Color?, Color, int)>[
      ('all', 'Xem tất cả công trình', null, Colors.white, mine.length + others.length),
      ('mine', 'Công trình của bạn', minePin, Colors.white, mine.length),
      ('fresh', 'Cập nhật chưa quá $days ngày', ageFresh, ageFreshLine, _n(true)),
      ('stale', 'Quá $days ngày: cần cập nhật', ageStale, Colors.white, _n(false)),
    ];
    final cur = opts.firstWhere((o) => o.$1 == filter);
    final box = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(R.card),
      border: Border.all(color: C.line),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
      if (filterOpen)
        Container(
          decoration: box,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            for (final o in opts)
              InkWell(
                onTap: () => setState(() {
                  filter = o.$1;
                  filterOpen = false;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                    Icon(filter == o.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: filter == o.$1 ? C.navy : C.subtle),
                    Flexible(child: _legend(o.$3, o.$2, line: o.$4)),
                    Text('(${o.$5})', style: const TextStyle(fontSize: 12.5, color: C.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => filterOpen = !filterOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: box.copyWith(borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              const Icon(Icons.filter_alt_outlined, size: 18, color: C.navy),
              Flexible(
                child: Text(filter == 'all' ? 'Lọc công trình' : cur.$2,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.navy)),
              ),
              Icon(filterOpen ? Icons.expand_more : Icons.expand_less, size: 18, color: C.navy),
            ]),
          ),
        ),
      ),
    ]);
  }

  // Chấm màu 20px (to gấp đôi); c = null: chừa chỗ trống cho thẳng hàng chữ
  Widget _legend(Color? c, String text, {Color line = Colors.white}) => Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        if (c == null)
          const SizedBox(width: 20, height: 20)
        else
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: line == Colors.white ? Colors.black12 : line, width: 1.5)),
          ),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.text))),
      ]);
}

/// Ghim định vị (giọt nước, lỗ tròn trắng giữa), mũi ghim ở đáy: đặt Marker với alignment topCenter.
class Pin extends StatelessWidget {
  const Pin({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PinPainter(color));
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    // Khung gốc 32 x 42 (giống ghim trên web)
    final sx = size.width / 32, sy = size.height / 42;
    final p = ui.Path()
      ..moveTo(16 * sx, 1.5 * sy)
      ..cubicTo(8.3 * sx, 1.5 * sy, 2 * sx, 7.7 * sy, 2 * sx, 15.4 * sy)
      ..cubicTo(2 * sx, 25.8 * sy, 16 * sx, 40.5 * sy, 16 * sx, 40.5 * sy)
      ..cubicTo(16 * sx, 40.5 * sy, 30 * sx, 25.8 * sy, 30 * sx, 15.4 * sy)
      ..cubicTo(30 * sx, 7.7 * sy, 23.7 * sx, 1.5 * sy, 16 * sx, 1.5 * sy)
      ..close();
    canvas.drawShadow(p, const Color(0xFF000000), 2, false);
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawPath(p, Paint()
      ..color = const Color(0x47000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    canvas.drawCircle(Offset(16 * sx, 15.4 * sy), 6.2 * sx, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}
