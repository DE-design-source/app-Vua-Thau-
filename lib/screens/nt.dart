// App cho tài khoản NHÀ THẦU (thiết kế "App Vua Thầu Map – Nhà thầu", đợt 1, 23/11/2026):
//   Trang chủ: lời chào + nút Chụp nhật ký hôm nay + thẻ công ty + Công trình của bạn (nhắc chưa cập nhật hôm nay)
//   Dự án (hồ sơ năng lực): lọc Tất cả / Đang thi công / Hoàn thành; Chi tiết: tiến độ, nhật ký thi công có giờ + GPS
//   Chụp ảnh: camera Vua Thầu (in giờ, địa chỉ, GPS) -> mô tả việc đã làm -> tải lên dự án
//   Bản đồ: các dự án của mình. (Khám phá, logo trên ảnh, chia sẻ hồ sơ: đợt sau.)
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../page.dart';
import '../stamp.dart' show StampData, p2;
import '../toast.dart';
import '../ui.dart';
import '../rating.dart';
import 'camera.dart';
import 'guest.dart' show GuestProject;
import 'nt_form.dart';
import 'nt_explore.dart';
import 'nt_logo.dart';
import 'nt_report.dart';
import 'home_shell.dart' show NavItem, ShootItem;

// màu theo thiết kế
const _ink = Color(0xFF0B2340), _gold = Color(0xFFFFB81C), _bg = Color(0xFFF4F6FA), _slate = Color(0xFF64748B);
const _blue = Color(0xFF0A4BB5), _chip = Color(0xFFEAF1FC), _green = Color(0xFF16A34A), _orange = Color(0xFFC2410C);

String ntPhoto(int id, {bool small = true}) => '$base/nt/photos/$id${small ? '?size=small' : ''}';

/// Ngày yyyy-mm-dd (giờ máy) của chuỗi thời gian máy chủ
DateTime? _day(Object? s) {
  final t = DateTime.tryParse(str(s));
  if (t == null) return null;
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

int _daysOf(Json p) {
  final start = _day(p['started_on']);
  if (start == null) return 1;
  final end = _day(p['finished_on']) ?? DateTime.now();
  return math.max(1, DateTime(end.year, end.month, end.day).difference(start).inDays + 1); // dữ liệu cũ: bắt đầu sau hoàn thành
}

/// "Cập nhật hôm nay / hôm qua / N ngày trước" (xanh) hoặc "Chưa cập nhật hôm nay" (cam)
(String, Color) _freshness(Json p) {
  if (p['status'] == 'hoan_thanh') return ('Đã hoàn thành', _slate);
  final last = _day(p['last_log']);
  if (last == null) return ('Chưa có nhật ký', _orange);
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day).difference(last).inDays;
  if (d <= 0) return ('Đã cập nhật hôm nay', _green);
  return ('Chưa cập nhật hôm nay · lần cuối ${d == 1 ? 'hôm qua' : '$d ngày trước'}', _orange);
}

/// Chữ viết tắt tên công ty: bỏ "Công ty, TNHH, Xây dựng..." (vd "Công ty TNHH Xây dựng Hùng Phát" -> "HP")
String _coInitials(String name) {
  var n = ' ${name.toLowerCase()} ';
  for (final w in [
    'công ty',
    'cty',
    'tnhh',
    'cổ phần',
    'cp',
    'xây dựng',
    'thương mại',
    'dịch vụ',
    'kiến trúc',
    'nội thất',
    'thiết kế',
    'một thành viên',
    'mtv',
    'và',
    '&',
  ]) {
    n = n.replaceAll(' $w ', ' ');
  }
  n = n.trim();
  return initials(n.isNotEmpty ? n : name).toUpperCase();
}

String _statusLabel(Object? s) => s == 'hoan_thanh' ? 'Hoàn thành' : 'Đang thi công';

// ---------------------------------------------------------------- khung tab

/// Đã tự mở camera lần đầu vào app chưa (1 lần mỗi lần mở app).
bool _autoCamDone = false;

/// "Lưu ảnh vào máy" (Cài đặt nhà thầu, lưu trên máy này): ảnh nhật ký lưu thêm vào thư viện ảnh khi tải lên.
final ntSaveDevice = ValueNotifier<bool>(false);
const _prefs = FlutterSecureStorage();

Future<void> loadSaveDevice() async {
  try {
    ntSaveDevice.value = await _prefs.read(key: 'nt_save_device') == '1';
  } catch (_) {}
}

Future<void> setSaveDevice(bool on) async {
  ntSaveDevice.value = on;
  try {
    await _prefs.write(key: 'nt_save_device', value: on ? '1' : '0');
  } catch (_) {}
}

class NtShell extends StatefulWidget {
  const NtShell({super.key});
  @override
  State<NtShell> createState() => _NtShellState();
}

class _NtShellState extends State<NtShell> {
  int tab = 0;
  final homeKey = GlobalKey<_NtHomeState>(), projKey = GlobalKey<_NtProjectsState>(), mapKey = GlobalKey<_NtMapState>();
  final exploreKey = GlobalKey<NtExploreState>();

  @override
  void initState() {
    super.initState();
    warmCamera();
    loadSaveDevice();
    // mở app là vào thẳng camera (góp ý 24/11/2026: tạo thói quen chụp mỗi ngày); đóng camera thì về Trang chủ
    if (!_autoCamDone) {
      _autoCamDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) shoot();
      });
    }
  }

  void reloadAll() {
    homeKey.currentState?.load();
    projKey.currentState?.load();
    mapKey.currentState?.load();
    exploreKey.currentState?.load();
  }

  Future<void> shoot() async {
    final done = await captureToday(context, bottomBar: navBar(camera: true));
    if (done == true) reloadAll();
    // đóng camera về Trang chủ: đủ 30 ảnh thì hỏi đánh giá app (mở app là vào camera nên hỏi ở đây)
    if (mounted) await checkRating();
    if (mounted) showRatingIfDue(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    body: IndexedStack(
      index: tab,
      children: [
        NtHome(key: homeKey, onChanged: reloadAll, goProjects: () => setState(() => tab = 1)),
        NtProjects(key: projKey, onChanged: reloadAll),
        NtExplore(key: exploreKey, map: NtMap(key: mapKey)),
      ],
    ),
    bottomNavigationBar: navBar(),
  );

  /// Thanh tab dưới. camera: true -> thanh hiện trong màn chụp (góp ý 24/11/2026: mở chụp ảnh vẫn hiện menu trắng, không
  /// đen cả đáy); "Chụp hình" đang chọn, bấm tab khác: đóng camera (ảnh chưa gửi thì camera hỏi trước) rồi chuyển tab.
  Widget navBar({bool camera = false}) => Builder(
    builder: (ctx) {
      void go(VoidCallback then) async {
        if (!camera) return then();
        if (await Navigator.of(ctx).maybePop() && mounted) then();
      }

      return Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: NavItem(label: 'Trang chủ', icon: Icons.home_outlined, iconOn: Icons.home, on: !camera && tab == 0, onTap: () => go(() => _go(0)))),
                Expanded(child: NavItem(label: 'Dự án', icon: Icons.work_outline, iconOn: Icons.work, on: !camera && tab == 1, onTap: () => go(() => _go(1)))),
                Expanded(child: ShootItem(on: camera, shutter: camera, onTap: shoot)),
                Expanded(child: NavItem(label: 'Khám phá', icon: Icons.explore_outlined, iconOn: Icons.explore, on: !camera && tab == 2, onTap: () => go(() => _go(2)))),
                Expanded(
                  child: NavItem(
                    label: 'Tài khoản',
                    icon: Icons.account_circle_outlined,
                    iconOn: Icons.account_circle,
                    on: false,
                    onTap: () => go(() => push(context, const NtAccount())),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _go(int i) {
    if (tab == i) {
      reloadAll();
    } else {
      setState(() => tab = i);
    }
  }
}

/// Chụp nhật ký hôm nay (nút Chụp hình / "Chụp nhật ký hôm nay"): vào camera ngay, chụp xong mới chọn dự án
/// (góp ý 24/11/2026: "Vào chụp ảnh trực tiếp không cần hỏi, chọn điền dự án vào sau").
Future<bool?> captureToday(BuildContext context, {Widget? bottomBar}) =>
    push<bool>(context, _ntCamera(null, bottomBar: bottomBar ?? context.findAncestorStateOfType<_NtShellState>()?.navBar(camera: true)));

/// Chọn dự án cho nhật ký vừa chụp: dự án đang thi công (mới cập nhật trước), dự án đã hoàn thành, hoặc tạo dự án mới.
Future<Json?> pickNtProject(BuildContext context) async {
  List<Json> rows;
  try {
    rows = ((await api('/nt/projects'))['rows'] as List? ?? const []).cast<Json>();
  } catch (e) {
    toast(errMsg(e));
    return null;
  }
  if (!context.mounted) return null;
  final active = rows.where((r) => r['status'] != 'hoan_thanh').toList(), done = rows.where((r) => r['status'] == 'hoan_thanh').toList();
  Widget tile(BuildContext ctx, Json r) => ListTile(
        leading: _cover(r, size: 44),
        title: Text(str(r['name']), style: T.bold, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${_statusLabel(r['status'])} · Ngày ${_daysOf(r)}', maxLines: 1),
        onTap: () => Navigator.pop(ctx, r),
      );
  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .75),
        child: ListView(shrinkWrap: true, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Nhật ký này của dự án nào?', style: T.secT)),
          for (final r in active) tile(ctx, r),
          if (done.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 4), child: Text('ĐÃ HOÀN THÀNH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: _slate))),
          for (final r in done) tile(ctx, r),
          ListTile(
            leading: const CircleAvatar(backgroundColor: _gold, child: Icon(Icons.add, color: _ink)),
            title: const Text('Tạo dự án mới', style: T.bold),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
        ]),
      ),
    ),
  );
  if (picked == 'new' && context.mounted) return editProject(context, null);
  return picked is Json ? picked : null;
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Camera chụp nhật ký cho dự án p (có vị trí dự án thì màn Xác nhận báo khớp GPS); p null: chụp trước, chọn dự án sau.
Widget _ntCamera(Json? p, {Widget? bottomBar}) {
  final b = ntBranding.value;
  return CameraScreen(
    ntProject: p == null ? 0 : asInt(p['id']),
    ntName: p == null ? '' : str(p['name']),
    ntLat: p == null ? null : _num(p['lat']),
    ntLng: p == null ? null : _num(p['lng']),
    ntPick: pickNtProject,
    ntSave: ntSaveDevice.value,
    ntStyle: _ntStyle,
    bottomBar: bottomBar,
    ntBrand: b.brand.isNotEmpty ? b.brand : ntCompany.value,
    ntLogo: b.logo,
    ntScale: b.scale,
    ntBadge: b.badge,
  );
}

/// Dải chữ nhà thầu theo hồ sơ mới nhất (tên công ty / thương hiệu / logo / cỡ / nhãn), đổi khi hồ sơ tải xong.
final _ntStyle = _NtStyle();

class _NtStyle extends ValueNotifier<StampData Function(StampData)> {
  _NtStyle() : super(_apply) {
    ntCompany.addListener(_bump);
    ntBranding.addListener(_bump);
  }
  void _bump() => value = (d) => _apply(d);
  static StampData _apply(StampData d) {
    final b = ntBranding.value;
    return StampData(d.date, d.pos, d.addr, brand: b.brand.isNotEmpty ? b.brand : ntCompany.value, logo: b.logo, scale: b.scale, badge: b.badge);
  }
}

/// Tên công ty (hồ sơ nhà thầu) in trên ảnh nhật ký; cập nhật khi Trang chủ / Tài khoản tải hồ sơ.
final ntCompany = ValueNotifier<String>('');

/// Logo trên ảnh: tên thương hiệu / logo công ty in lên ảnh nhật ký, cỡ, nhãn Vua Thầu xác minh (hồ sơ nhà thầu).
class NtBranding {
  const NtBranding({this.brand = '', this.logo, this.size = 2, this.badge = true, this.hasLogo = false});
  final String brand; // tên thương hiệu nhập tay (trống: in tên công ty)
  final ui.Image? logo;
  final int size; // 1 nhỏ, 2 vừa, 3 lớn
  final bool badge, hasLogo;
  double get scale => const {1: 0.8, 2: 1.0, 3: 1.25}[size] ?? 1.0;
}

final ntBranding = ValueNotifier<NtBranding>(const NtBranding());

/// Đọc cấu hình Logo trên ảnh từ hồ sơ; có logo thì tải file về (in lên ảnh khi chụp).
Future<void> loadBranding(Json prof, {bool force = false}) async {
  final hasLogo = prof['has_logo'] == true;
  ui.Image? logo = hasLogo && !force ? ntBranding.value.logo : null;
  if (hasLogo && logo == null) {
    try {
      final r = await http.get(Uri.parse('$base/nt/logo'), headers: authHeaders());
      if (r.statusCode == 200) logo = (await (await ui.instantiateImageCodec(r.bodyBytes)).getNextFrame()).image;
    } catch (_) {/* không tải được: in tên dạng chữ */}
  }
  ntBranding.value = NtBranding(
    brand: str(prof['brand']),
    logo: logo,
    size: asInt(prof['logo_size']) > 0 ? asInt(prof['logo_size']) : 2,
    badge: prof['show_badge'] != false,
    hasLogo: hasLogo,
  );
}

/// Hồ sơ công ty (khu vực...) từ Trang chủ: đầu trang Dự án dùng lại.
final ntProfile = ValueNotifier<Json>({});

/// "Chia sẻ" hồ sơ năng lực: link /nt/<mã> (khách mở xem công ty + các dự án + báo cáo).
Future<void> sharePortfolio(BuildContext context) async {
  try {
    final j = await api('/nt/portfolio');
    final url = '$host${str(j['path'])}';
    final text = 'Hồ sơ năng lực ${ntCompany.value.isNotEmpty ? ntCompany.value : 'của chúng tôi'}: các công trình đã và đang thi công, '
        'ảnh thực tế có giờ chụp + GPS.\n$url';
    try {
      final r = await SharePlus.instance.share(ShareParams(text: text, subject: 'Hồ sơ năng lực'));
      if (r.status == ShareResultStatus.unavailable) throw Exception('unavailable');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      toast('Đã chép link hồ sơ năng lực. Dán vào Zalo / Messenger gửi khách.');
    }
  } catch (e) {
    toast(errMsg(e));
  }
}

/// Tạo / sửa dự án: form "Đăng tải dự án mới" (nt_form.dart). Trả dự án đã lưu, null nếu đóng.
Future<Json?> editProject(BuildContext context, Json? p) => editProjectForm(context, p);

// ---------------------------------------------------------------- Trang chủ

class NtHome extends StatefulWidget {
  const NtHome({super.key, required this.onChanged, required this.goProjects});
  final VoidCallback onChanged, goProjects;
  @override
  State<NtHome> createState() => _NtHomeState();
}

class _NtHomeState extends State<NtHome> with PageData {
  @override
  String get path => '/nt/home';
  @override
  bool get watchRoute => false;

  @override
  void onData(Json j) {
    final prof = (j['profile'] as Map?) ?? const {};
    final user = (j['user'] as Map?) ?? const {};
    ntCompany.value = str(prof['company']).isNotEmpty ? str(prof['company']) : str(user['name']);
    ntProfile.value = prof.cast<String, dynamic>();
    loadBranding(ntProfile.value);
  }

  String _greet() {
    final h = DateTime.now().hour;
    return h < 11
        ? 'Chào buổi sáng!'
        : h < 14
        ? 'Chào buổi trưa!'
        : h < 18
        ? 'Chào buổi chiều!'
        : 'Chào buổi tối!';
  }

  String _today() {
    const wd = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
    final n = DateTime.now();
    return '${wd[n.weekday - 1]}, ${n.day} tháng ${n.month}';
  }

  @override
  Widget build(BuildContext context) {
    final j = d;
    final prof = (j?['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    final user = (j?['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final stats = (j?['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final projects = ((j?['projects'] as List?) ?? const []).cast<Json>();
    final sites = ((j?['sites'] as List?) ?? const []).cast<Json>();
    final company = str(prof['company']).isNotEmpty ? str(prof['company']) : str(user['name']);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Nền xanh đầu trang vẽ phía SAU, kéo xuống đỡ nửa trên nút "Chụp nhật ký hôm nay".
          // (Trước đây nút bị Transform.translate dời lên đè vào đầu trang: phần nằm ngoài ô của nó không bấm được.)
          Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).padding.top + 200,
                child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B2340), Color(0xFF102C5E), Color(0xFF1B3F94)]))),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Brand(size: 36),
                    SizedBox(width: 10),
                    Text.rich(
                      TextSpan(
                        text: 'Vua Thầu ',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                        children: [TextSpan(text: 'Map', style: TextStyle(color: _gold))],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(_today(), style: const TextStyle(color: Color(0xFF9FB3CF), fontSize: 12)),
                const SizedBox(height: 2),
                Text(_greet(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                const SizedBox(height: 2),
                const Text('Hôm nay bạn đang thi công ở đâu?', style: TextStyle(color: Color(0xFFC9D4E5), fontSize: 13)),
              ],
            ),
          ),
                Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Chụp nhật ký hôm nay
                  Material(
                    color: _gold,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 6,
                    shadowColor: _gold.withValues(alpha: .5),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        if (await captureToday(context) == true) widget.onChanged();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          spacing: 14,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(border: Border.all(color: _ink, width: 3), borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.photo_camera, color: _ink),
                            ),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Chụp nhật ký hôm nay', style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                                  Text('Tự động lưu ngày giờ & GPS', style: TextStyle(color: _ink, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: _ink),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // thẻ công ty
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        Row(
                          spacing: 12,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(14)),
                              child: Text(_coInitials(company), style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w800)),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 3,
                                children: [
                                  Text(
                                    company.isNotEmpty ? company : 'Công ty của bạn',
                                    style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    [
                                      if (asInt(prof['reviews']) > 0) '★ ${prof['rating']} · ${prof['reviews']} đánh giá',
                                      if (asInt(prof['years']) > 0) '${prof['years']} năm KN',
                                      if (asInt(prof['reviews']) == 0 && asInt(prof['years']) == 0) 'Cập nhật hồ sơ công ty ở Tài khoản',
                                    ].join(' · '),
                                    style: const TextStyle(color: _slate, fontSize: 11),
                                  ),
                                  if (prof['verified'] == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(999)),
                                      child: const Text('Đã xác minh', style: TextStyle(color: Color(0xFF8A5A00), fontSize: 10, fontWeight: FontWeight.w800)),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (((prof['specialties'] as List?) ?? const []).isNotEmpty || str(prof['regions']).isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final s in ((prof['specialties'] as List?) ?? const [])) _pill(str(s), _chip, _blue),
                              if (str(prof['regions']).isNotEmpty) _pill(str(prof['regions']), const Color(0xFFF1F5F9), const Color(0xFF475569)),
                            ],
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Expanded(child: _stat('${asInt(stats['projects']) + asInt(stats['sites'])}', 'Dự án')),
                              Container(width: 1, height: 28, color: const Color(0xFFE3E8F0)),
                              Expanded(child: _stat('${stats['logs'] ?? 0}', 'Nhật ký')),
                              Container(width: 1, height: 28, color: const Color(0xFFE3E8F0)),
                              Expanded(child: _stat(_thousands(asInt(stats['views'])), 'Lượt xem')),
                            ],
                          ),
                        ),
                        // thiết kế: "Đăng dự án" | "Báo cáo KH" (chữ 1 dòng, không xuống dòng ở máy hẹp)
                        Row(
                          spacing: 10,
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _blue,
                                  minimumSize: const Size.fromHeight(44),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () async {
                                  if (await editProject(context, null) != null) widget.onChanged();
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const FittedBox(child: Text('Đăng dự án', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800))),
                              ),
                            ),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _blue,
                                  minimumSize: const Size.fromHeight(44),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  side: const BorderSide(color: Color(0xFFC9D8F2)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => openLatestReport(context, projects),
                                icon: const Icon(Icons.description_outlined, size: 18),
                                label: const FittedBox(child: Text('Báo cáo KH', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800))),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Text('Công trình của bạn', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800))),
                      if (projects.isNotEmpty) TextButton(onPressed: widget.goProjects, child: const Text('Xem tất cả')),
                    ],
                  ),
                  if (j == null) Loading(err: err, retry: load),
                  if (j != null && projects.isEmpty && sites.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Chưa có dự án. Bấm "Đăng dự án" để tạo, rồi chụp nhật ký hằng ngày.', style: T.muted),
                    ),
                  for (final p in projects.take(6)) Padding(padding: const EdgeInsets.only(top: 10), child: _ProjectRow(p: p, onChanged: widget.onChanged)),
                  // công trình CTV đã chụp có bảng hiệu ghi SĐT của nhà thầu (đồng bộ theo SĐT tài khoản)
                  if (sites.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const Text('Công trình Vua Thầu ghi nhận', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    const Text('CTV Vua Thầu đã chụp, bảng hiệu ghi số điện thoại của bạn.', style: TextStyle(color: _slate, fontSize: 12)),
                    for (final s in sites) Padding(padding: const EdgeInsets.only(top: 10), child: NtSiteRow(s: s, onChanged: widget.onChanged)),
                  ],
                ],
              ),
            ),
              ],
            ),
          ],
        ),
        ],
      ),
    );
  }
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// "Báo cáo KH" (góp ý 24/11/2026): mở danh sách dự án (lưới như trang Dự án) để chọn dự án gửi báo cáo cho khách.
Future<void> openLatestReport(BuildContext context, [List<Json> projects = const []]) => push(context, const NtReportPick());

/// Báo cáo nhật ký mới nhất của dự án p (chưa có nhật ký: nhắc chụp trước).
Future<void> _reportOf(BuildContext context, Json p) async {
  if (asInt(p['logs']) == 0) {
    toast('Dự án này chưa có nhật ký. Chụp nhật ký hôm nay rồi gửi báo cáo cho khách.');
    return;
  }
  try {
    final j = await api('/nt/projects/${p['id']}');
    final logs = ((j['logs'] as List?) ?? const []).cast<Json>();
    if (logs.isEmpty || !context.mounted) return;
    await push(context, NtReportScreen(projectId: asInt(p['id']), logId: asInt(logs.first['id'])));
  } catch (e) {
    toast(errMsg(e));
  }
}

class NtReportPick extends StatefulWidget {
  const NtReportPick({super.key});
  @override
  State<NtReportPick> createState() => _NtReportPickState();
}

class _NtReportPickState extends State<NtReportPick> {
  List<Json>? rows;
  String err = '', filter = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final j = await api('/nt/projects');
      if (mounted) setState(() => rows = ((j['rows'] as List?) ?? const []).cast<Json>());
    } catch (e) {
      if (mounted) setState(() => err = errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = rows;
    final list = all == null ? const <Json>[] : all.where((p) => filter.isEmpty || p['status'] == filter).toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        title: const Text('Gửi báo cáo cho khách', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: all == null
          ? Loading(err: err, retry: load)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('Chọn dự án để gửi báo cáo nhật ký mới nhất.', style: T.muted)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(spacing: 8, children: [
                  for (final (k, label) in const [('', 'Tất cả'), ('dang_thi_cong', 'Đang thi công'), ('hoan_thanh', 'Hoàn thành')])
                    ChoiceChip(
                      label: Text(label),
                      selected: filter == k,
                      showCheckmark: false,
                      selectedColor: _ink,
                      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: filter == k ? Colors.white : _ink),
                      onSelected: (_) => setState(() => filter = k),
                    ),
                ]),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Chưa có dự án.', style: T.muted)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .74),
                        itemCount: list.length,
                        itemBuilder: (context, i) => _ProjectCard(p: list[i], onChanged: () {}, onTap: () => _reportOf(context, list[i])),
                      ),
              ),
            ]),
    );
  }
}

Widget _card(Widget child) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: const [BoxShadow(color: Color(0x0F0B2340), blurRadius: 2, offset: Offset(0, 1))],
  ),
  child: child,
);

Widget _pill(String s, Color bg, Color fg) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
  child: Text(s, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
);

Widget _stat(String n, String label) => Column(
  children: [
    Text(n, style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
    Text(label, style: const TextStyle(color: _slate, fontSize: 10, fontWeight: FontWeight.w600)),
  ],
);

/// Ảnh bìa dự án: ảnh của nhà thầu; dự án nhận từ công trình CTV chưa có ảnh thì ảnh CTV (link công khai cover_url).
Widget _coverImage(Json p, {bool small = true, double? width, double? height}) {
  final c = asInt(p['cover']);
  final url = str(p['cover_url']);
  if (c > 0) return NetPhoto(ntPhoto(c, small: small), width: width, height: height);
  if (url.isNotEmpty) {
    return Image.network('$host$url', width: width, height: height, fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(width: width, height: height, color: const Color(0xFFE3E8F0)));
  }
  return Container(width: width, height: height, color: const Color(0xFFE3E8F0), child: const Icon(Icons.apartment, color: _slate));
}

Widget _cover(Json p, {double size = 64, double radius = 10}) =>
    ClipRRect(borderRadius: BorderRadius.circular(radius), child: _coverImage(p, width: size, height: size));

/// Chụp nhật ký vào công trình Vua Thầu ghi nhận: nhận công trình thành dự án của mình (1 lần) rồi mở camera.
Future<bool> shootSite(BuildContext context, int hid) async {
  Json? p;
  try {
    p = (await post('/nt/sites/$hid/claim'))['project'] as Json?;
  } catch (e) {
    toast(errMsg(e));
    return false;
  }
  if (p == null || !context.mounted) return false;
  return await push<bool>(context, _ntCamera(p)) == true;
}

/// 1 công trình Vua Thầu ghi nhận (CTV chụp, bảng hiệu có SĐT nhà thầu): ảnh bìa công khai, địa chỉ, giai đoạn, ngày chụp.
class NtSiteRow extends StatelessWidget {
  const NtSiteRow({super.key, required this.s, this.onChanged});
  final Json s;
  final VoidCallback? onChanged; // vừa chụp nhật ký (công trình thành dự án của mình): tải lại
  @override
  Widget build(BuildContext context) {
    final cover = str(s['cover_url']);
    final t = DateTime.tryParse(str(s['at']))?.toLocal();
    final addr = str(s['address']);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final hid = asInt(s['id']);
          await push(context, GuestProject(id: hid, signedIn: true, onShoot: (ctx) => shootSite(ctx, hid)));
          onChanged?.call();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            spacing: 12,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: cover.isNotEmpty
                    ? Image.network('$host$cover', width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 64, height: 64, color: const Color(0xFFE3E8F0)))
                    : Container(width: 64, height: 64, color: const Color(0xFFE3E8F0), child: const Icon(Icons.apartment, color: _slate)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(addr.isNotEmpty ? addr : 'Công trình', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(
                      [str(s['stage']), str(s['province_name']), if (t != null) 'chụp ${p2(t.day)}/${p2(t.month)}', '${s['photos'] ?? 0} ảnh']
                          .where((x) => x.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _slate, fontSize: 12),
                    ),
                    const SizedBox(height: 3),
                    _pill('Vua Thầu ghi nhận', _chip, _blue),
                  ],
                ),
              ),
              // chụp nhật ký vào công trình này luôn
              IconButton.filledTonal(
                tooltip: 'Chụp nhật ký',
                style: IconButton.styleFrom(backgroundColor: _gold, foregroundColor: _ink),
                onPressed: () async {
                  if (await shootSite(context, asInt(s['id']))) onChanged?.call();
                },
                icon: const Icon(Icons.photo_camera, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.p, required this.onChanged});
  final Json p;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final (fresh, col) = _freshness(p);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await push(context, NtProjectDetail(id: asInt(p['id'])));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            spacing: 12,
            children: [
              _cover(p),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(str(p['name']), style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('${_statusLabel(p['status'])} · Ngày ${_daysOf(p)}', style: const TextStyle(color: _slate, fontSize: 12)),
                    const SizedBox(height: 3),
                    Row(
                      spacing: 5,
                      children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                        Flexible(child: Text(fresh, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _slate),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Dự án (hồ sơ năng lực)

class NtProjects extends StatefulWidget {
  const NtProjects({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<NtProjects> createState() => _NtProjectsState();
}

class _NtProjectsState extends State<NtProjects> with PageData {
  String status = '';
  @override
  String get path => '/nt/projects${status.isEmpty ? '' : '?status=$status'}';
  @override
  bool get watchRoute => false;
  List<Json> sites = []; // công trình Vua Thầu ghi nhận theo SĐT (hiện ở "Tất cả")

  @override
  void onData(Json j) {
    api('/nt/sites').then((s) {
      if (mounted) setState(() => sites = ((s['rows'] as List?) ?? const []).cast<Json>());
    }).catchError((Object _) {/* không có: chỉ hiện dự án tự đăng */});
  }

  Widget _sitesSection() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Công trình Vua Thầu ghi nhận', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          const Text('CTV Vua Thầu đã chụp, bảng hiệu ghi số điện thoại của bạn.', style: TextStyle(color: _slate, fontSize: 12)),
          for (final s in sites) Padding(padding: const EdgeInsets.only(top: 10), child: NtSiteRow(s: s, onChanged: widget.onChanged)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final rows = ((d?['rows'] as List?) ?? const []).cast<Json>();
    final showSites = status.isEmpty && sites.isNotEmpty;
    final prof = ntProfile.value;
    final company = ntCompany.value;
    final logs = rows.fold<int>(0, (a, p) => a + asInt(p['logs']));
    return Column(
      children: [
        // thiết kế "Dự án (Portfolio)": đầu trang + thẻ công ty (số dự án, nhật ký) + Chia sẻ hồ sơ năng lực
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 8, 14),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B2340), Color(0xFF102C5E), Color(0xFF1B3F94)])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dự án', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('Hồ sơ năng lực của bạn', style: TextStyle(color: Color(0xFFC9D4E5), fontSize: 13)),
                ]),
              ),
              IconButton(tooltip: 'Chia sẻ hồ sơ năng lực', onPressed: () => sharePortfolio(context), icon: const Icon(Icons.ios_share, color: Colors.white)),
            ]),
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(spacing: 10, children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(12)),
                  child: Text(company.isEmpty ? 'NT' : _coInitials(company), style: const TextStyle(color: _gold, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(company.isEmpty ? 'Công ty của bạn' : company,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(['Nhà thầu xây dựng', if (str(prof['regions']).isNotEmpty) str(prof['regions'])].join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _slate, fontSize: 11.5)),
                  ]),
                ),
                _stat('${rows.length + sites.length}', 'Dự án'),
                const SizedBox(width: 4),
                _stat('$logs', 'Nhật ký'),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            spacing: 8,
            children: [
              for (final (v, label) in const [('', 'Tất cả'), ('dang_thi_cong', 'Đang thi công'), ('hoan_thanh', 'Hoàn thành')])
                ChoiceChip(
                  label: Text(label),
                  selected: status == v,
                  showCheckmark: false,
                  selectedColor: _ink,
                  labelStyle: TextStyle(color: status == v ? Colors.white : _ink, fontWeight: FontWeight.w700, fontSize: 13),
                  onSelected: (_) {
                    setState(() => status = v);
                    load();
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child:
                d == null
                    ? ListView(children: [Loading(err: err, retry: load)])
                    : rows.isEmpty && showSites
                    ? ListView(children: [_sitesSection()])
                    : rows.isNotEmpty && showSites
                    ? ListView(
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 12,
                            childAspectRatio: .74,
                          ),
                          itemCount: rows.length,
                          itemBuilder: (context, i) => _ProjectCard(p: rows[i], onChanged: widget.onChanged),
                        ),
                        _sitesSection(),
                      ],
                    )
                    : rows.isEmpty
                    ? ListView(
                      children: [
                        Empty(
                          icon: 'building',
                          title: 'Chưa có dự án',
                          text: 'Đăng tải dự án đang làm, chụp nhật ký mỗi ngày để có hồ sơ năng lực gửi chủ nhà.',
                          cta: 'Đăng tải dự án',
                          onTap: () async {
                            if (await editProject(context, null) != null) widget.onChanged();
                          },
                        ),
                      ],
                    )
                    : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 12,
                        childAspectRatio: .74,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _ProjectCard(p: rows[i], onChanged: widget.onChanged),
                    ),
          ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.p, required this.onChanged, this.onTap});
  final Json p;
  final VoidCallback onChanged;

  /// onTap: thay cho mở chi tiết dự án (VD chọn dự án gửi báo cáo).
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final done = p['status'] == 'hoan_thanh';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap ??
          () async {
            await push(context, NtProjectDetail(id: asInt(p['id'])));
            onChanged();
          },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(builder: (c, b) => _cover(p, size: b.maxWidth, radius: 12)),
                Positioned(left: 8, top: 8, child: _pill(_statusLabel(p['status']), done ? const Color(0xFFE8F5E9) : Colors.white, done ? _green : _ink)),
                Positioned(right: 8, bottom: 8, child: _pill('${p['photos'] ?? 0} ảnh', Colors.black.withValues(alpha: .55), Colors.white)),
              ],
            ),
          ),
          Text(str(p['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
          Text(
            [if (str(p['address']).isNotEmpty) str(p['address']).split(',').first, '${_daysOf(p)} ngày'].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _slate, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Chi tiết dự án

class NtProjectDetail extends StatefulWidget {
  const NtProjectDetail({super.key, required this.id});
  final int id;
  @override
  State<NtProjectDetail> createState() => _NtProjectDetailState();
}

class _NtProjectDetailState extends State<NtProjectDetail> with PageData {
  @override
  String get path => '/nt/projects/${widget.id}';

  Future<void> setStatus(Json p) async {
    final done = p['status'] == 'hoan_thanh';
    if (!done && !await confirm(context, title: 'Đánh dấu hoàn thành?', text: 'Dự án chuyển sang Hoàn thành, tiến độ 100%.', ok: 'Hoàn thành', danger: false)) {
      return;
    }
    try {
      final j = await put('/nt/projects/${widget.id}', {
        'name': p['name'],
        'address': p['address'],
        'kind': p['kind'],
        'status': done ? 'dang_thi_cong' : 'hoan_thanh',
      });
      toast(str(j['message']));
      load();
    } catch (e) {
      toast(errMsg(e));
    }
  }

  Future<void> remove(Json p) async {
    if (!await confirm(context, title: 'Xoá dự án ${p['name']}?', text: 'Dự án và nhật ký sẽ không còn trong hồ sơ năng lực.', ok: 'Xoá')) return;
    try {
      toast(str((await delete('/nt/projects/${widget.id}'))['message']));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(errMsg(e));
    }
  }

  Future<void> removeLog(Json l) async {
    if (!await confirm(context, title: 'Xoá nhật ký này?', text: str(l['note']), ok: 'Xoá')) return;
    try {
      toast(str((await delete('/nt/projects/${widget.id}/logs/${l['id']}'))['message']));
      load();
    } catch (e) {
      toast(errMsg(e));
    }
  }

  /// Gửi báo cáo cho chủ nhà: nhật ký mới nhất (thiết kế: nút Chia sẻ).
  void shareLatest(List<Json> logs) {
    if (logs.isEmpty) {
      toast('Chưa có nhật ký. Chụp nhật ký hôm nay rồi gửi báo cáo cho khách.');
      return;
    }
    push(context, NtReportScreen(projectId: widget.id, logId: asInt(logs.first['id'])));
  }

  /// Giữ lâu 1 nhật ký: gửi báo cáo / xoá.
  void logMenu(Json l) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: _blue),
              title: const Text('Gửi báo cáo cho khách'),
              onTap: () {
                Navigator.pop(ctx);
                push(context, NtReportScreen(projectId: widget.id, logId: asInt(l['id'])));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: C.bad),
              title: const Text('Xoá nhật ký', style: TextStyle(color: C.bad)),
              onTap: () {
                Navigator.pop(ctx);
                removeLog(l);
              },
            ),
          ]),
        ),
      );

  Future<void> more(Json p) async {
    final done = p['status'] == 'hoan_thanh';
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Sửa dự án, tiến độ'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
            leading: Icon(done ? Icons.replay : Icons.task_alt),
            title: Text(done ? 'Chuyển về Đang thi công' : 'Đánh dấu Hoàn thành'),
            onTap: () => Navigator.pop(ctx, 'status'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: C.bad),
            title: const Text('Xoá dự án', style: TextStyle(color: C.bad)),
            onTap: () => Navigator.pop(ctx, 'del'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    final have = ((d?['photos'] as List?) ?? const []).length;
    if (v == 'edit' && await editProject(context, {...p, 'photos_project': have}) != null) load();
    if (v == 'status') setStatus(p);
    if (v == 'del') remove(p);
  }

  Widget _round(IconData icon, String tip, VoidCallback onTap) => Material(
        color: const Color(0x800B2340),
        shape: const CircleBorder(),
        child: IconButton(tooltip: tip, onPressed: onTap, icon: Icon(icon, color: Colors.white, size: 20)),
      );

  Widget _section(List<Widget> children) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  @override
  Widget build(BuildContext context) {
    final p = (d?['project'] as Map?)?.cast<String, dynamic>();
    final logs = ((d?['logs'] as List?) ?? const []).cast<Json>();
    if (p == null) return Scaffold(appBar: AppBar(), body: Loading(err: err, retry: load));
    final done = p['status'] == 'hoan_thanh';
    final progress = done ? 100 : asInt(p['progress']);
    final latest = logs.isNotEmpty ? logs.first : null;
    // ảnh dự án (form Đăng dự án, không thuộc nhật ký): dự án đăng kèm ảnh / đã hoàn thành chưa có nhật ký vẫn hiện ảnh
    final Json photos = {'media': ((d?['photos'] as List?) ?? const []).cast<Json>()};
    final hasPhotos = (photos['media'] as List).isNotEmpty;
    void openPhotos(List<int> ids, int i) => push(context, _Viewer(ids: ids, start: i, title: str(p['name'])));
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // ---- ảnh bìa + tên dự án (thiết kế "Chi tiết dự án") ----
        SizedBox(
          height: 230 + top,
          child: Stack(fit: StackFit.expand, children: [
            asInt(p['cover']) > 0 || str(p['cover_url']).isNotEmpty ? _coverImage(p, small: false) : Container(color: const Color(0xFF9FB6D1)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .35, .55, 1],
                  colors: [Color(0x8C0B2340), Color(0x000B2340), Color(0x000B2340), Color(0xD90B2340)],
                ),
              ),
            ),
            Positioned(
              top: top + 12,
              left: 12,
              right: 12,
              child: Row(children: [
                _round(Icons.arrow_back, 'Quay lại', () => Navigator.pop(context)),
                const Spacer(),
                _round(Icons.ios_share, 'Chia sẻ dự án', () => shareLatest(logs)),
                const SizedBox(width: 8),
                _round(Icons.more_horiz, 'Thêm tùy chọn', () => more(p)),
              ]),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: done ? _green : _blue, borderRadius: BorderRadius.circular(999)),
                  child: Text(_statusLabel(p['status']), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 6),
                Text(str(p['name']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                if (str(p['address']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(spacing: 4, children: [
                      const Icon(Icons.place, size: 13, color: Color(0xFFC9D4E5)),
                      Expanded(
                        child: Text(str(p['address']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFC9D4E5), fontSize: 12)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(padding: EdgeInsets.zero, children: [
              // ---- cập nhật mới nhất + tiến độ ----
              _section([
                Text(latest == null && hasPhotos ? 'ẢNH DỰ ÁN' : 'CẬP NHẬT MỚI NHẤT',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: _blue)),
                const SizedBox(height: 4),
                if (latest == null && hasPhotos)
                  _LogPhotos(log: photos, max: 5, onOpen: openPhotos)
                else if (latest == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Chưa có nhật ký. Bấm "Chụp nhật ký hôm nay" để bắt đầu.', style: T.muted),
                  )
                else ...[
                  Text(_fullTime(latest['taken_at']), style: const TextStyle(fontSize: 12, color: _slate)),
                  _LogPhotos(log: latest, max: 5, onOpen: (ids, i) => push(context, _Viewer(ids: ids, start: i, title: str(p['name']), at: latest['taken_at']))),
                  if (str(latest['note']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('“${str(latest['note'])}”', style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF1E293B))),
                    ),
                  _Videos(log: latest),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Expanded(child: Text('Tiến độ công trình', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _ink))),
                      Text(done ? 'Đã hoàn thành' : '$progress%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _blue)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: progress / 100, minHeight: 6, color: _blue, backgroundColor: const Color(0xFFD7DEE7)),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _stat('${d?['days'] ?? _daysOf(p)}', 'Ngày')),
                      Expanded(child: _stat('${p['logs'] ?? 0}', 'Nhật ký')),
                      Expanded(child: _stat('${p['photos'] ?? 0}', 'Ảnh')),
                      Expanded(child: _stat('${p['videos'] ?? 0}', 'Video')),
                    ]),
                  ]),
                ),
              ]),
              // ---- ảnh dự án (khi đã có nhật ký thì ảnh dự án ở mục riêng) ----
              if (latest != null && hasPhotos) ...[
                const SizedBox(height: 8),
                _section([
                  const Text('Ảnh dự án', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 8),
                  _LogPhotos(log: photos, max: 5, onOpen: openPhotos),
                ]),
              ],
              // ---- nhật ký trước đây ----
              if (logs.length > 1) ...[
                const SizedBox(height: 8),
                _section([
                  const Text('Nhật ký trước đây', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                  for (final l in logs.skip(1))
                    _LogItem(
                      l: l,
                      onOpen: (ids, i) => push(context, _Viewer(ids: ids, start: i, title: str(p['name']), at: l['taken_at'])),
                      onMenu: () => logMenu(l),
                    ),
                ]),
              ],
              if (latest != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text('Giữ lâu 1 nhật ký để gửi báo cáo cho khách hoặc xoá.', textAlign: TextAlign.center, style: T.muted.copyWith(fontSize: 11.5)),
                ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
        // ---- Chia sẻ | Chụp nhật ký hôm nay ----
        Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE3E8F0)))),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
          child: Row(spacing: 10, children: [
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side: const BorderSide(color: _blue, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => shareLatest(logs),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Chia sẻ', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            if (!done)
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () async {
                      if (await push<bool>(context, _ntCamera({...p, 'id': widget.id})) == true) load();
                    },
                    icon: const Icon(Icons.photo_camera),
                    label: const FittedBox(child: Text('Chụp nhật ký hôm nay', style: TextStyle(fontWeight: FontWeight.w800))),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

const _wd = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

/// "Thứ Hai, 23/11/2026 · 08:19"
String _fullTime(Object? at) {
  final t = DateTime.tryParse(str(at))?.toLocal();
  if (t == null) return '';
  return '${_wd[t.weekday - 1]}, ${p2(t.day)}/${p2(t.month)}/${t.year} · ${p2(t.hour)}:${p2(t.minute)}';
}

/// Ảnh ghép của 1 nhật ký (thiết kế): hàng 1 = ảnh dọc + ảnh ngang, hàng 2 = 3 ảnh; small: 1 hàng 3 ảnh; ảnh thừa "+N".
class _LogPhotos extends StatelessWidget {
  const _LogPhotos({required this.log, required this.onOpen, this.max = 5, this.small = false});
  final Json log;
  final int max;
  final bool small;
  final void Function(List<int> ids, int start) onOpen;

  @override
  Widget build(BuildContext context) {
    final ids = [
      for (final m in ((log['media'] as List?) ?? const []).cast<Json>())
        if (m['kind'] == 'photo') asInt(m['id']),
    ];
    if (ids.isEmpty) return const SizedBox.shrink();
    final shown = ids.take(max).toList();
    final more = ids.length - shown.length;
    Widget tile(int i, {double ratio = 3 / 4, int flex = 100}) => Expanded(
          flex: flex,
          child: AspectRatio(
            aspectRatio: ratio,
            child: GestureDetector(
              onTap: () => onOpen(ids, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(fit: StackFit.expand, children: [
                  NetPhoto(ntPhoto(shown[i])),
                  if (i == shown.length - 1 && more > 0)
                    Container(
                      color: const Color(0x8C0B2340),
                      alignment: Alignment.center,
                      child: Text(small ? '+$more' : '+$more ảnh', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
            ),
          ),
        );
    if (small) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(spacing: 5, children: [
          for (var i = 0; i < 3; i++) i < shown.length ? tile(i, ratio: 1) : const Expanded(child: SizedBox()),
        ]),
      );
    }
    final first = shown.take(2).toList(), second = shown.length > 2 ? shown.sublist(2) : <int>[];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(spacing: 5, children: [
        Row(spacing: 5, children: [
          if (first.length == 1) tile(0, ratio: 4 / 3) else ...[tile(0, flex: 75), tile(1, ratio: 4 / 3, flex: 133)],
        ]),
        if (second.isNotEmpty)
          Row(spacing: 5, children: [
            for (var k = 0; k < 3; k++) k < second.length ? tile(k + 2) : const Expanded(child: SizedBox()),
          ]),
      ]),
    );
  }
}

/// Video của nhật ký: link xem (có chữ ký).
class _Videos extends StatelessWidget {
  const _Videos({required this.log});
  final Json log;
  @override
  Widget build(BuildContext context) {
    final vs = ((log['media'] as List?) ?? const []).cast<Json>().where((m) => m['kind'] == 'video').toList();
    if (vs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 12, children: [
        for (var k = 0; k < vs.length; k++)
          InkWell(
            onTap: () => launchUrl(Uri.parse('$host${str(vs[k]['src'])}'), mode: LaunchMode.externalApplication),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                const Icon(Icons.play_circle_fill, color: _blue, size: 22),
                Text(vs.length > 1 ? 'Video ${k + 1}' : 'Xem video', style: const TextStyle(color: _blue, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// 1 dòng "Nhật ký trước đây": ngày, việc đã làm, 3 ảnh nhỏ (+N); bấm xem ảnh, giữ lâu: gửi báo cáo / xoá.
class _LogItem extends StatelessWidget {
  const _LogItem({required this.l, required this.onOpen, required this.onMenu});
  final Json l;
  final void Function(List<int> ids, int start) onOpen;
  final VoidCallback onMenu;
  @override
  Widget build(BuildContext context) {
    final t = DateTime.tryParse(str(l['taken_at']))?.toLocal();
    final ids = [
      for (final m in ((l['media'] as List?) ?? const []).cast<Json>())
        if (m['kind'] == 'photo') asInt(m['id']),
    ];
    return InkWell(
      onTap: ids.isEmpty ? onMenu : () => onOpen(ids, 0),
      onLongPress: onMenu,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF1F6)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 8, children: [
            Text(t == null ? '' : '${p2(t.day)}/${p2(t.month)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink, fontFeatures: [FontFeature.tabularFigures()])),
            Expanded(
              child: Text(str(l['note']).isNotEmpty ? str(l['note']) : 'Nhật ký thi công',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
            ),
            if (l['lat'] != null) _pill('GPS', const Color(0xFFE8F5E9), _green),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
          ]),
          _LogPhotos(log: l, small: true, max: 3, onOpen: onOpen),
          _Videos(log: l),
        ]),
      ),
    );
  }
}

/// Xem ảnh lớn, vuốt qua lại; đầu trang "2 / 9" + tên dự án · ngày.
class _Viewer extends StatefulWidget {
  const _Viewer({required this.ids, required this.start, this.title = '', this.at});
  final List<int> ids;
  final int start;
  final String title;
  final Object? at;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int i = widget.start;
  late final ctl = PageController(initialPage: widget.start);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DateTime.tryParse(str(widget.at))?.toLocal();
    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05080F),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(children: [
          Text('${i + 1} / ${widget.ids.length}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          if (widget.title.isNotEmpty)
            Text('${widget.title}${t != null ? ' · ${p2(t.day)}/${p2(t.month)}' : ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1))),
        ]),
      ),
      body: PageView(
        controller: ctl,
        onPageChanged: (k) => setState(() => i = k),
        children: [for (final id in widget.ids) InteractiveViewer(child: Center(child: NetPhoto(ntPhoto(id, small: false), fit: BoxFit.contain)))],
      ),
    );
  }
}

// ---------------------------------------------------------------- Bản đồ dự án

class NtMap extends StatefulWidget {
  const NtMap({super.key});
  @override
  State<NtMap> createState() => _NtMapState();
}

class _NtMapState extends State<NtMap> with PageData {
  @override
  String get path => '/nt/projects';
  @override
  bool get watchRoute => false;
  final ctl = MapController();

  @override
  Widget build(BuildContext context) {
    final rows = ((d?['rows'] as List?) ?? const []).cast<Json>().where((p) => p['lat'] != null && p['lng'] != null).toList();
    final pts = [for (final p in rows) LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())];
    return Stack(
      children: [
        FlutterMap(
          mapController: ctl,
          options: MapOptions(
            initialCenter: pts.isNotEmpty ? pts.first : const LatLng(10.78, 106.70),
            initialZoom: pts.isNotEmpty ? 13 : 11,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            TileLayer(urlTemplate: '$host/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'vn.com.vuathau', maxNativeZoom: 19),
            MarkerLayer(
              markers: [
                for (var i = 0; i < rows.length; i++)
                  Marker(
                    point: pts[i],
                    width: 140,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => push(context, NtProjectDetail(id: asInt(rows[i]['id']))),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              str(rows[i]['name']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Icon(Icons.location_on, color: _gold, size: 28),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (d != null && rows.isEmpty)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 12,
            child: _card(const Text('Dự án hiện trên bản đồ sau lần chụp nhật ký đầu tiên (lấy vị trí GPS).', style: T.muted)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Tài khoản (hồ sơ công ty)

class NtAccount extends StatefulWidget {
  const NtAccount({super.key});
  @override
  State<NtAccount> createState() => _NtAccountState();
}

class _NtAccountState extends State<NtAccount> with PageData {
  @override
  String get path => '/nt/home';
  final company = TextEditingController(), regions = TextEditingController(), years = TextEditingController();
  Set<String> specs = {};
  bool saving = false, filled = false;
  String version = '';
  static const all = ['Nhà phố', 'Biệt thự', 'Căn hộ', 'Sửa chữa', 'Nội thất', 'Văn phòng'];

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => version = p.version);
    });
  }

  @override
  void onData(Json j) {
    if (filled) return;
    filled = true;
    final p = (j['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    company.text = str(p['company']);
    regions.text = str(p['regions']);
    years.text = asInt(p['years']) > 0 ? '${p['years']}' : '';
    specs = {for (final s in ((p['specialties'] as List?) ?? const [])) str(s)};
  }

  @override
  void dispose() {
    company.dispose();
    regions.dispose();
    years.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final j = await put('/nt/profile', {
        'company': company.text.trim(),
        'regions': regions.text.trim(),
        'years': int.tryParse(years.text.trim()) ?? 0,
        'specialties': specs.toList(),
      });
      if (company.text.trim().isNotEmpty) ntCompany.value = company.text.trim(); // tên in trên ảnh nhật ký
      toast(str(j['message']));
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = (d?['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = company.text.trim().isNotEmpty ? company.text.trim() : str(user['name']);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body:
          d == null
              ? Loading(err: err, retry: load)
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // thẻ đầu trang như thiết kế "Cài đặt nhà thầu": chữ cái đầu + tên công ty
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                    child: Row(
                      spacing: 12,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: _ink,
                          child: Text(name.isEmpty ? 'N' : _coInitials(name), style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: T.bold, maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text('Nhà thầu · ${str(user['username'])}', style: T.muted),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ẢNH & THƯƠNG HIỆU (thiết kế "Cài đặt nhà thầu")
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text('ẢNH & THƯƠNG HIỆU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: Color(0xFF94A3B8))),
                  ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: Column(children: [
                      ListTile(
                        leading: const Icon(Icons.branding_watermark_outlined, color: _blue),
                        title: const Text('Logo trên ảnh', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(ntBranding.value.hasLogo ? 'Logo công ty' : 'Thay bằng logo công ty bạn'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await push(context, const NtLogoScreen());
                          if (mounted) setState(() {});
                        },
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(Icons.ios_share, color: _blue),
                        title: const Text('Chia sẻ hồ sơ năng lực', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Gửi link các dự án của bạn cho khách'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => sharePortfolio(context),
                      ),
                      const Divider(height: 1, indent: 16),
                      ValueListenableBuilder<bool>(
                        valueListenable: ntSaveDevice,
                        builder: (context, on, _) => SwitchListTile(
                          secondary: const Icon(Icons.download_outlined, color: _blue),
                          title: const Text('Lưu ảnh vào máy', style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(kIsWeb ? 'Tải ảnh nhật ký xuống máy khi tải lên' : 'Lưu ảnh nhật ký vào thư viện ảnh (album Vua Thầu)'),
                          value: on,
                          activeTrackColor: _green,
                          onChanged: setSaveDevice,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Box(
                    gap: 14,
                    children: [
                      const Text('Hồ sơ công ty', style: T.bold),
                      Field(label: 'Tên công ty', controller: company, placeholder: 'Công ty TNHH Xây dựng ...'),
                      Field(label: 'Khu vực hoạt động', controller: regions, placeholder: 'TP.HCM · Bình Dương'),
                      Field(label: 'Số năm kinh nghiệm', controller: years, keyboardType: TextInputType.number),
                      const Text('Nhận làm', style: T.cap),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in all)
                            FilterChip(label: Text(s), selected: specs.contains(s), onSelected: (on) => setState(() => on ? specs.add(s) : specs.remove(s))),
                        ],
                      ),
                      Btn('Lưu hồ sơ công ty', kind: BtnKind.primary, busy: saving, onPressed: save),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Btn(
                    'Đăng xuất',
                    onPressed: () async {
                      if (await confirm(context, title: 'Đăng xuất?', text: 'Lần sau mở app, nhập số điện thoại là vào lại.', ok: 'Đăng xuất')) {
                        await setToken(null);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // CH Play bắt buộc: tự xoá tài khoản ngay trong app
                  TextButton(
                    onPressed: () async {
                      if (!await confirm(context,
                          title: 'Xoá vĩnh viễn tài khoản?',
                          text: 'Hồ sơ năng lực, link báo cáo gửi chủ nhà sẽ không mở được nữa. Không khôi phục được.',
                          ok: 'Xoá tài khoản')) {
                        return;
                      }
                      try {
                        final j = await delete('/me');
                        await setToken(null); // màn gốc tự về đăng nhập
                        toast(msgsOf(j));
                      } catch (e) {
                        if (loggedIn()) toast(errMsg(e));
                      }
                    },
                    child: Text('Xoá tài khoản', style: TextStyle(color: C.subtle)),
                  ),
                  const SizedBox(height: 16),
                  Center(child: Text('Vua Thầu Map${version.isNotEmpty ? ' · phiên bản $version' : ''}', style: T.cap.copyWith(color: C.subtle))),
                ],
              ),
    );
  }
}
