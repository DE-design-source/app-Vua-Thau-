// App cho tài khoản NHÀ THẦU (thiết kế "App Vua Thầu Map – Nhà thầu", đợt 1, 23/11/2026):
//   Trang chủ: lời chào + nút Chụp nhật ký hôm nay + thẻ công ty + Công trình của bạn (nhắc chưa cập nhật hôm nay)
//   Dự án (hồ sơ năng lực): lọc Tất cả / Đang thi công / Hoàn thành; Chi tiết: tiến độ, nhật ký thi công có giờ + GPS
//   Chụp ảnh: camera Vua Thầu (in giờ, địa chỉ, GPS) -> mô tả việc đã làm -> tải lên dự án
//   Bản đồ: các dự án của mình. (Khám phá, logo trên ảnh, chia sẻ hồ sơ: đợt sau.)
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../page.dart';
import '../stamp.dart' show p2;
import '../toast.dart';
import '../ui.dart';
import 'camera.dart';
import 'nt_form.dart';
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
  return DateTime(end.year, end.month, end.day).difference(start).inDays + 1;
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

class NtShell extends StatefulWidget {
  const NtShell({super.key});
  @override
  State<NtShell> createState() => _NtShellState();
}

class _NtShellState extends State<NtShell> {
  int tab = 0;
  final homeKey = GlobalKey<_NtHomeState>(), projKey = GlobalKey<_NtProjectsState>(), mapKey = GlobalKey<_NtMapState>();

  @override
  void initState() {
    super.initState();
    warmCamera();
  }

  void reloadAll() {
    homeKey.currentState?.load();
    projKey.currentState?.load();
    mapKey.currentState?.load();
  }

  Future<void> shoot() async {
    final done = await captureToday(context);
    if (done == true) reloadAll();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    body: IndexedStack(
      index: tab,
      children: [
        NtHome(key: homeKey, onChanged: reloadAll, goProjects: () => setState(() => tab = 1)),
        NtProjects(key: projKey, onChanged: reloadAll),
        NtMap(key: mapKey),
      ],
    ),
    bottomNavigationBar: Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: NavItem(label: 'Trang chủ', icon: Icons.home_outlined, iconOn: Icons.home, on: tab == 0, onTap: () => _go(0))),
              Expanded(child: NavItem(label: 'Dự án', icon: Icons.work_outline, iconOn: Icons.work, on: tab == 1, onTap: () => _go(1))),
              Expanded(child: ShootItem(on: false, onTap: shoot)),
              Expanded(child: NavItem(label: 'Bản đồ', icon: Icons.map_outlined, iconOn: Icons.map, on: tab == 2, onTap: () => _go(2))),
              Expanded(
                child: NavItem(
                  label: 'Tài khoản',
                  icon: Icons.account_circle_outlined,
                  iconOn: Icons.account_circle,
                  on: false,
                  onTap: () => push(context, const NtAccount()),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _go(int i) {
    if (tab == i) {
      reloadAll();
    } else {
      setState(() => tab = i);
    }
  }
}

/// Chụp nhật ký hôm nay: chưa có dự án -> tạo; 1 dự án đang thi công -> chụp luôn; nhiều -> chọn dự án.
Future<bool?> captureToday(BuildContext context) async {
  Json j;
  try {
    j = await api('/nt/projects?status=dang_thi_cong');
  } catch (e) {
    toast(errMsg(e));
    return false;
  }
  if (!context.mounted) return false;
  var rows = ((j['rows'] as List?) ?? const []).cast<Json>();
  Json? p;
  if (rows.isEmpty) {
    toast('Tạo dự án trước, rồi chụp nhật ký cho dự án đó.');
    p = await editProject(context, null);
  } else if (rows.length == 1) {
    p = rows.first;
  } else {
    p = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Chụp nhật ký cho dự án nào?', style: T.secT)),
                for (final r in rows)
                  ListTile(
                    leading: const Icon(Icons.apartment, color: _ink),
                    title: Text(str(r['name']), style: T.bold),
                    subtitle: Text('${_statusLabel(r['status'])} · Ngày ${_daysOf(r)}'),
                    onTap: () => Navigator.pop(ctx, r),
                  ),
              ],
            ),
          ),
    );
  }
  if (p == null || !context.mounted) return false;
  return push<bool>(context, _ntCamera(p));
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Camera chụp nhật ký cho dự án p (có vị trí dự án thì màn Xác nhận báo khớp GPS).
Widget _ntCamera(Json p) =>
    CameraScreen(ntProject: asInt(p['id']), ntName: str(p['name']), ntLat: _num(p['lat']), ntLng: _num(p['lng']), ntBrand: ntCompany.value);

/// Tên công ty (hồ sơ nhà thầu) in trên ảnh nhật ký; cập nhật khi Trang chủ / Tài khoản tải hồ sơ.
final ntCompany = ValueNotifier<String>('');

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
    final company = str(prof['company']).isNotEmpty ? str(prof['company']) : str(user['name']);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 16, 72),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B2340), Color(0xFF102C5E), Color(0xFF1B3F94)])),
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
          Transform.translate(
            offset: const Offset(0, -52),
            child: Padding(
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
                              Expanded(child: _stat('${stats['projects'] ?? 0}', 'Dự án')),
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
                  if (j != null && projects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Chưa có dự án. Bấm "Đăng tải dự án" để tạo, rồi chụp nhật ký hằng ngày.', style: T.muted),
                    ),
                  for (final p in projects.take(6)) Padding(padding: const EdgeInsets.only(top: 10), child: _ProjectRow(p: p, onChanged: widget.onChanged)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// "Báo cáo KH": báo cáo nhật ký mới nhất (nhiều dự án có nhật ký thì chọn dự án).
Future<void> openLatestReport(BuildContext context, List<Json> projects) async {
  final withLogs = projects.where((p) => asInt(p['logs']) > 0).toList();
  if (withLogs.isEmpty) {
    toast('Chưa có nhật ký nào. Chụp nhật ký hôm nay rồi gửi báo cáo cho khách.');
    return;
  }
  var p = withLogs.first;
  if (withLogs.length > 1) {
    final picked = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Gửi báo cáo dự án nào?', style: T.secT)),
            for (final r in withLogs)
              ListTile(
                leading: const Icon(Icons.apartment, color: _ink),
                title: Text(str(r['name']), style: T.bold),
                subtitle: Text('${r['logs']} nhật ký · ${_freshness(r).$1}'),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    p = picked;
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

Widget _cover(Json p, {double size = 64, double radius = 10}) {
  final c = asInt(p['cover']);
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child:
        c > 0
            ? NetPhoto(ntPhoto(c), width: size, height: size)
            : Container(width: size, height: size, color: const Color(0xFFE3E8F0), child: const Icon(Icons.apartment, color: _slate)),
  );
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

  @override
  Widget build(BuildContext context) {
    final rows = ((d?['rows'] as List?) ?? const []).cast<Json>();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 16, 14),
          color: _ink,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dự án', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              Text('Hồ sơ năng lực của bạn', style: TextStyle(color: Color(0xFFC9D4E5), fontSize: 13)),
            ],
          ),
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
  const _ProjectCard({required this.p, required this.onChanged});
  final Json p;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final done = p['status'] == 'hoan_thanh';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
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

  @override
  Widget build(BuildContext context) {
    final p = (d?['project'] as Map?)?.cast<String, dynamic>();
    final logs = ((d?['logs'] as List?) ?? const []).cast<Json>();
    if (p == null) return Scaffold(appBar: AppBar(), body: Loading(err: err, retry: load));
    final done = p['status'] == 'hoan_thanh';
    final progress = asInt(p['progress']);
    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 240,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  asInt(p['cover']) > 0 ? NetPhoto(ntPhoto(asInt(p['cover']), small: true)) : Container(color: _ink),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66000000), Color(0x00000000), Color(0xCC0B2340)],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Row(
                      children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          onSelected: (v) async {
                            final have = ((d?['photos'] as List?) ?? const []).length;
                            if (v == 'edit' && context.mounted && await editProject(context, {...p, 'photos_project': have}) != null) load();
                            if (v == 'status') setStatus(p);
                            if (v == 'del') remove(p);
                          },
                          itemBuilder:
                              (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('Sửa dự án, tiến độ')),
                                PopupMenuItem(value: 'status', child: Text(done ? 'Chuyển về Đang thi công' : 'Đánh dấu Hoàn thành')),
                                const PopupMenuItem(value: 'del', child: Text('Xoá dự án', style: TextStyle(color: C.bad))),
                              ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        _pill(_statusLabel(p['status']), done ? const Color(0xFFE8F5E9) : _gold, done ? _green : _ink),
                        Text(str(p['name']), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        if (str(p['address']).isNotEmpty) Text(str(p['address']), style: const TextStyle(color: Color(0xFFC9D4E5), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('Tiến độ', style: TextStyle(color: _ink, fontWeight: FontWeight.w800))),
                            Text('$progress%', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(value: progress / 100, minHeight: 8, color: _gold, backgroundColor: const Color(0xFFE3E8F0)),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: _stat('${d?['days'] ?? _daysOf(p)}', 'Ngày')),
                            Expanded(child: _stat('${p['logs'] ?? 0}', 'Nhật ký')),
                            Expanded(child: _stat('${p['photos'] ?? 0}', 'Ảnh')),
                            Expanded(child: _stat('${p['videos'] ?? 0}', 'Video')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Text('Nhật ký thi công', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
                  if (logs.isEmpty) const Text('Chưa có nhật ký. Bấm "Chụp nhật ký hôm nay" để bắt đầu.', style: T.muted),
                  for (final l in logs)
                    _LogItem(
                      l: l,
                      onDelete: () => removeLog(l),
                      onShare: () => push(context, NtReportScreen(projectId: widget.id, logId: asInt(l['id']))),
                    ),
                  const SizedBox(height: 70),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton:
          done
              ? null
              : FloatingActionButton.extended(
                backgroundColor: _gold,
                foregroundColor: _ink,
                onPressed: () async {
                  if (await push<bool>(context, _ntCamera({...p, 'id': widget.id})) == true) load();
                },
                icon: const Icon(Icons.photo_camera),
                label: const Text('Chụp nhật ký hôm nay', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
    );
  }
}

class _LogItem extends StatelessWidget {
  const _LogItem({required this.l, required this.onDelete, required this.onShare});
  final Json l;
  final VoidCallback onDelete, onShare;
  @override
  Widget build(BuildContext context) {
    final t = DateTime.tryParse(str(l['taken_at']))?.toLocal();
    final media = ((l['media'] as List?) ?? const []).cast<Json>();
    final photos = media.where((m) => m['kind'] == 'photo').toList();
    return GestureDetector(
      onLongPress: onDelete,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Text(t == null ? '' : '${p2(t.day)}/${p2(t.month)}', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 13)),
                Text(t == null ? '' : '${p2(t.hour)}:${p2(t.minute)}', style: const TextStyle(color: _slate, fontSize: 11)),
                if (l['lat'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: _pill('GPS', const Color(0xFFE8F5E9), _green)),
              ],
            ),
          ),
          Expanded(
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(str(l['note']).isNotEmpty ? str(l['note']) : 'Nhật ký thi công', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                      ),
                      // gửi báo cáo nhật ký này cho chủ nhà; giữ lâu cả thẻ để xoá
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_horiz, color: _slate, size: 20),
                        onSelected: (v) => v == 'share' ? onShare() : onDelete(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'share', child: Text('Gửi báo cáo cho khách')),
                          PopupMenuItem(value: 'del', child: Text('Xoá nhật ký', style: TextStyle(color: C.bad))),
                        ],
                      ),
                    ],
                  ),
                  if (photos.isNotEmpty)
                    Row(
                      spacing: 6,
                      children: [
                        for (var k = 0; k < photos.length && k < 3; k++)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => push(context, _Viewer(ids: [for (final x in photos) asInt(x['id'])], start: k)),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(borderRadius: BorderRadius.circular(8), child: NetPhoto(ntPhoto(asInt(photos[k]['id'])))),
                                    if (k == 2 && photos.length > 3)
                                      Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          '+${photos.length - 3}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // luôn 3 ô: nhật ký 1-2 ảnh không bị phình to
                        for (var k = photos.length; k < 3; k++) const Expanded(child: SizedBox()),
                      ],
                    ),
                  for (final v in media.where((m) => m['kind'] == 'video'))
                    InkWell(
                      onTap: () => launchUrl(Uri.parse('$host${str(v['src'])}'), mode: LaunchMode.externalApplication),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          spacing: 6,
                          children: [
                            Icon(Icons.play_circle_fill, color: _blue, size: 22),
                            Text('Xem video', style: TextStyle(color: _blue, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Xem ảnh lớn, vuốt qua lại.
class _Viewer extends StatelessWidget {
  const _Viewer({required this.ids, required this.start});
  final List<int> ids;
  final int start;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
    body: PageView(
      controller: PageController(initialPage: start),
      children: [for (final id in ids) InteractiveViewer(child: Center(child: NetPhoto(ntPhoto(id, small: false), fit: BoxFit.contain)))],
    ),
  );
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
                  const SizedBox(height: 16),
                  Center(child: Text('Vua Thầu Map${version.isNotEmpty ? ' · phiên bản $version' : ''}', style: T.cap.copyWith(color: C.subtle))),
                ],
              ),
    );
  }
}
