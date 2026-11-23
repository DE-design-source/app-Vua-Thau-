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
final Future<vmt.Style> mapStyle = vmt.StyleReader(uri: '$host/map-style.json').read();

// Công trình theo lần chụp: chưa quá số ngày chặn trùng vàng nhạt, quá thì xanh lá (cần cập nhật, được chụp lại)
// vàng: chụp chưa quá hạn (giống web); xanh lá tươi: cần cập nhật
const ageFresh = Color(0xFFF5B301), ageFreshLine = Color(0xFFB7791F), ageStale = Color(0xFF22C55E);
const minePin = C.blue; // công trình của mình: ghim xanh dương
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
      // công trình của mình khớp tên / SĐT nhà thầu, địa chỉ (máy chủ chỉ trả của mình) + địa điểm trên bản đồ
      final sites = [
        for (final x in ((j['sites'] as List?) ?? const []).cast<Json>())
          <String, dynamic>{
            'name': str(x['contractor']).isNotEmpty ? str(x['contractor']) : str(x['address']),
            'sub': str(x['contractor']).isNotEmpty ? str(x['address']) : '',
            'lat': x['lat'],
            'lng': x['lng'],
            'site': true,
          },
      ];
      final ps = [...sites, ...((j['places'] as List?) ?? const []).cast<Json>()];
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
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
              Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: C.muted), children: [
                const TextSpan(text: 'Mã số '),
                TextSpan(text: hsId(p['id']), style: const TextStyle(fontWeight: FontWeight.w600, color: C.text, letterSpacing: 0.3)),
              ])),
              StatusBadge(str(p['status'])),
            ]),
            Text(str(p['address']).isNotEmpty ? str(p['address']) : '(chưa có địa chỉ)',
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: C.text, height: 1.25, letterSpacing: -0.3)),
            if (str(p['at']).isNotEmpty) Text('Chụp lần cuối ${str(p['at'])}', style: T.muted),
            const SizedBox(height: 6),
            Row(spacing: 10, children: [
              Expanded(
                child: Btn('Google Maps', icon: 'pin', onPressed: () => launchUrl(Uri.parse(gmapUrl(lat, lng)), mode: LaunchMode.externalApplication)),
              ),
              Expanded(
                child: Btn('Mở hồ sơ', kind: BtnKind.primary, onPressed: () {
                  Navigator.of(ctx).pop();
                  push(context, HouseScreen(id: asInt(p['id'])));
                }),
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
                future: mapStyle,
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
                    color: C.blue.withValues(alpha: .07),
                    borderColor: C.blue,
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
                        color: C.blue,
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
          // Ô tìm địa điểm + kết quả + số công trình trong vòng; dưới là hàng lọc (kiêm chú thích màu ghim)
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _searchBox()),
              _chips(dup > 0 ? dup : 30),
            ]),
          ),
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
              foregroundColor: C.text,
              elevation: 3,
              shape: const CircleBorder(),
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
      border: Border.all(color: C.line2),
      boxShadow: cardShadow,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Container(
        decoration: box.copyWith(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.only(left: 18, right: 6),
        height: 56,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => find(),
              style: const TextStyle(fontSize: 14.5, color: C.text),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Tìm địa chỉ, công ty, nhà thầu…',
                hintStyle: TextStyle(color: C.muted, fontSize: 14.5),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (hits != null || place != null)
            IconButton(
              tooltip: 'Xoá tìm kiếm',
              icon: const Icon(Icons.close, size: 20, color: C.text),
              onPressed: () => setState(() {
                q.clear();
                hits = null;
                place = null;
              }),
            ),
          // nút tìm tròn vàng (như bản web)
          Semantics(
            button: true,
            label: 'Tìm',
            child: Material(
              color: C.amber,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: finding ? null : find,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: finding
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.amberInk))
                        : const Icon(Icons.search, color: C.amberInk, size: 22),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      if (hits != null && hits!.length > 1 && place == null)
        Container(
          decoration: box,
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
            for (final h in hits!)
              ListTile(
                dense: true,
                leading: Icon(h['site'] == true ? Icons.home_work_outlined : Icons.place_outlined, size: 20, color: h['site'] == true ? minePin : C.muted),
                title: Text(str(h['name']), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: str(h['sub']).isNotEmpty ? Text(str(h['sub']), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                onTap: () => pick(h),
              ),
          ]),
        ),
      if (place != null)
        Container(
          decoration: box,
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                child: Text('Chọn kết quả khác (${hits!.length})', style: const TextStyle(color: C.text, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
              ),
          ]),
        ),
    ]);
  }

  /// Hàng lọc viên tròn cuộn ngang (kiêm chú thích màu ghim). Đang chọn: nền đen chữ trắng.
  Widget _chips(int days) {
    final opts = <(String, String, Color?, int)>[
      ('all', 'Tất cả', null, mine.length + others.length),
      ('mine', 'Của bạn', minePin, mine.length),
      ('fresh', 'Chưa quá $days ngày', ageFresh, _n(true)),
      ('stale', 'Cần cập nhật', ageStale, _n(false)),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: opts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, k) {
          final o = opts[k];
          final on = filter == o.$1;
          return Semantics(
            selected: on,
            button: true,
            child: Material(
              color: on ? C.text : Colors.white,
              elevation: 2,
              shadowColor: const Color(0x33000000),
              shape: StadiumBorder(side: BorderSide(color: on ? C.text : C.line2)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => setState(() => filter = o.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 7, children: [
                    if (o.$3 != null)
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: o.$3, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                      ),
                    Text(o.$2, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? Colors.white : C.text)),
                    Text('${o.$4}', style: TextStyle(fontSize: 12.5, color: on ? Colors.white70 : C.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }


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
