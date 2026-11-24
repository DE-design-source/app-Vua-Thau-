// Form "Đăng tải dự án mới" của nhà thầu (thiết kế 24/11/2026):
//   Tên dự án*, Địa chỉ*: Tỉnh / Thành phố* + Phường / Xã* (danh sách sau sắp xếp 2025) + số nhà, tên đường,
//   dòng xem trước địa chỉ + "Ghim trên bản đồ", Loại công trình, Hình ảnh dự án (ảnh bìa ở ô đầu, tối đa 20), nút Tạo dự án.
// Không ghim thì máy chủ tự tra toạ độ theo địa chỉ.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../lfile.dart';
import '../toast.dart';
import '../ui.dart';

const _ink = Color(0xFF0B2340), _blue = Color(0xFF0A4BB5), _chip = Color(0xFFEAF1FC), _line = Color(0xFFD5DDE8);
const _slate = Color(0xFF64748B), _red = Color(0xFFDC2626);
const maxProjectPhotos = 20;
const projectKinds = ['Nhà phố', 'Biệt thự', 'Căn hộ', 'Sửa chữa', 'Văn phòng', 'Khác'];

// ---------------------------------------------------------------- tỉnh / phường

class Division {
  Division(this.name, this.full, this.wards);
  final String name, full;
  final List<String> wards;
}

Future<List<Division>>? _divs;

/// 34 tỉnh / thành + phường / xã (GET /geo/divisions, tải 1 lần mỗi phiên; lỗi thì lần sau tải lại).
Future<List<Division>> divisions() => _divs ??= () async {
      try {
        final r = await http.get(Uri.parse('$base/geo/divisions')).timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) throw ApiError('Không tải được danh sách tỉnh / phường.');
        final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
        return [
          for (final d in list.cast<Map>())
            Division('${d['name']}', '${d['full']}', ((d['wards'] as List?) ?? const []).map((w) => '$w').toList()),
        ];
      } catch (e) {
        _divs = null;
        rethrow;
      }
    }();

/// Bỏ dấu, chữ thường: tìm "an khanh" ra "Phường An Khánh".
String fold(String s) {
  const a = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const b = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = a.indexOf(ch);
    out.write(i >= 0 ? b[i] : ch);
  }
  return out.toString();
}

/// Bảng chọn có ô tìm (tỉnh / phường). Trả mục đã chọn, null nếu đóng.
Future<String?> pickFrom(BuildContext context, String title, List<String> items, {String hint = 'Tìm'}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _PickSheet(title: title, items: items, hint: hint),
    );

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.title, required this.items, required this.hint});
  final String title, hint;
  final List<String> items;
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final k = fold(q.trim());
    // khớp trọn từ xếp trước: "an khanh" ra "Phường An Khánh" trước "Phường Tân Khánh"
    int rank(String x) {
      final f = fold(x);
      return f.endsWith(' $k') || f == k ? 0 : (f.contains(' $k') || f.startsWith(k) ? 1 : 2);
    }

    final rows = k.isEmpty ? widget.items : (widget.items.where((x) => fold(x).contains(k)).toList()..sort((a, b) => rank(a).compareTo(rank(b))));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Không có kết quả.', style: T.muted))
              : ListView.separated(
                  padding: EdgeInsets.only(bottom: 16 + MediaQuery.viewInsetsOf(context).bottom),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                  itemBuilder: (_, i) => ListTile(title: Text(rows[i]), onTap: () => Navigator.pop(context, rows[i])),
                ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- form

/// Tạo / sửa dự án (bảng trượt). Trả dự án đã lưu, null nếu đóng.
Future<Json?> editProjectForm(BuildContext context, Json? p) => showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => ProjectForm(p: p),
    );

class ProjectForm extends StatefulWidget {
  const ProjectForm({super.key, this.p});
  final Json? p;
  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  late final name = TextEditingController(text: str(widget.p?['name']));
  late final street = TextEditingController(text: str(widget.p?['street']));
  late String prov = str(widget.p?['province']), ward = str(widget.p?['ward']), kind = str(widget.p?['kind']);
  late double progress = asInt(widget.p?['progress']).toDouble();
  // Tình trạng: dự án mới mặc định Đang thi công; Đã hoàn thành thì chọn Năm hoàn thành
  late String status = str(widget.p?['status']).isNotEmpty ? str(widget.p?['status']) : 'dang_thi_cong';
  late int year = DateTime.tryParse(str(widget.p?['finished_on']))?.year ?? DateTime.now().year;

  Widget _statusOpt(String v, String label) {
    final on = status == v;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : () => setState(() => status = v),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? _chip : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? _blue : _line, width: on ? 1.5 : 1),
          ),
          child: Row(spacing: 8, children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: on ? _blue : _slate),
            Flexible(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? _blue : const Color(0xFF334155)))),
          ]),
        ),
      ),
    );
  }
  LatLng? pin; // ghim tay trên bản đồ (null: máy chủ tra theo địa chỉ)
  final photos = <XFile>[];
  bool busy = false;
  double? pct;
  String err = '';

  bool get editing => widget.p != null;
  int get havePhotos => asInt(widget.p?['photos_project']);

  @override
  void initState() {
    super.initState();
    street.addListener(() => setState(() {}));
    name.addListener(() => setState(() {}));
    divisions().ignore(); // tải sẵn danh sách
  }

  @override
  void dispose() {
    name.dispose();
    street.dispose();
    super.dispose();
  }

  String get preview => [street.text.trim(), ward, prov].where((s) => s.isNotEmpty).join(', ');

  Future<void> chooseProv() async {
    try {
      final ds = await divisions();
      if (!mounted) return;
      final v = await pickFrom(context, 'Tỉnh / Thành phố', [for (final d in ds) d.name], hint: 'Tìm tỉnh, thành phố');
      if (v != null && v != prov) setState(() => (prov = v, ward = '', pin = null));
    } catch (e) {
      toast(errMsg(e));
    }
  }

  Future<void> chooseWard() async {
    if (prov.isEmpty) {
      toast('Chọn tỉnh / thành phố trước.');
      return;
    }
    try {
      final ds = await divisions();
      final d = ds.where((x) => x.name == prov).firstOrNull;
      if (d == null || !mounted) return;
      final v = await pickFrom(context, 'Phường / Xã · ${d.name}', d.wards, hint: 'Tìm phường, xã');
      if (v != null && v != ward) setState(() => (ward = v, pin = null));
    } catch (e) {
      toast(errMsg(e));
    }
  }

  Future<void> choosePin() async {
    final p = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => PinPage(start: pin ?? _saved(), query: preview)),
    );
    if (p != null) setState(() => pin = p);
  }

  LatLng? _saved() {
    final la = widget.p?['lat'], ln = widget.p?['lng'];
    return la is num && ln is num ? LatLng(la.toDouble(), ln.toDouble()) : null;
  }

  Future<void> addPhotos() async {
    final room = maxProjectPhotos - havePhotos - photos.length;
    if (room <= 0) {
      toast('Dự án tối đa $maxProjectPhotos ảnh.');
      return;
    }
    try {
      final xs = await ImagePicker().pickMultiImage(maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
      if (xs.isEmpty || !mounted) return;
      if (xs.length > room) toast('Chỉ thêm được $room ảnh nữa (tối đa $maxProjectPhotos).');
      setState(() => photos.addAll(xs.take(room)));
    } catch (e) {
      toast('Không mở được thư viện ảnh.');
    }
  }

  Future<void> save() async {
    final miss = [if (name.text.trim().isEmpty) 'tên dự án', if (prov.isEmpty) 'tỉnh / thành phố', if (ward.isEmpty) 'phường / xã'];
    if (miss.isNotEmpty) {
      setState(() => err = 'Cần ${miss.join(', ')}.');
      return;
    }
    setState(() {
      busy = true;
      err = '';
    });
    try {
      final body = {
        'name': name.text.trim(),
        'province': prov,
        'ward': ward,
        'street': street.text.trim(),
        'kind': kind,
        if (pin != null) 'lat': pin!.latitude,
        if (pin != null) 'lng': pin!.longitude,
        'status': status,
        if (status == 'hoan_thanh') 'finished_year': year,
        if (editing && status != 'hoan_thanh') 'progress': progress.round(),
      };
      final j = editing ? await put('/nt/projects/${widget.p!['id']}', body) : await post('/nt/projects', body);
      final proj = (j['project'] as Map?)?.cast<String, dynamic>();
      if (proj != null && photos.isNotEmpty) {
        setState(() => pct = 0);
        try {
          final u = await upload(
            '/nt/projects/${proj['id']}/photos',
            [for (var i = 0; i < photos.length; i++) UpFile('files', photos[i].path, 'du-an-${i + 1}.jpg')],
            onProgress: (p) {
              if (mounted) setState(() => pct = p);
            },
          );
          toast('${str(j['message']).isNotEmpty ? str(j['message']) : 'Đã lưu dự án.'} ${str(u['message'])}');
        } catch (e) {
          toast('Đã lưu dự án nhưng chưa tải được ảnh: ${errMsg(e)} Mở dự án để thêm ảnh lại.');
        }
      } else {
        toast(str(j['message']).isNotEmpty ? str(j['message']) : 'Đã lưu dự án.');
      }
      if (mounted) Navigator.pop(context, proj);
    } catch (e) {
      if (mounted) setState(() => err = errMsg(e));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          pct = null;
        });
      }
    }
  }

  Widget _label(String s, {bool req = false}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text.rich(TextSpan(
          text: s,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _ink),
          children: [if (req) const TextSpan(text: ' *', style: TextStyle(color: _red))],
        )),
      );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _blue, width: 1.5)),
      );

  Widget _select(String label, String value, String empty, VoidCallback onTap, {bool enabled = true}) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 7, 8, 8),
            decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12), color: enabled ? Colors.white : const Color(0xFFF7F9FC)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text.rich(TextSpan(
                    text: label,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _slate),
                    children: const [TextSpan(text: ' *', style: TextStyle(color: _red))],
                  )),
                  Text(
                    value.isEmpty ? empty : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: value.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF0B1B33)),
                  ),
                ]),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 18, color: _slate),
            ]),
          ),
        ),
      );

  Widget _photoTile(int i) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          localImage(photos[i].path, fit: BoxFit.cover, cacheWidth: 400),
          if (i == 0 && havePhotos == 0)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(999)),
                child: const Text('Ảnh bìa', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          Positioned(
            right: 4,
            top: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : () => setState(() => photos.removeAt(i)),
                child: const Padding(padding: EdgeInsets.all(5), child: Icon(Icons.close, size: 16, color: Colors.white)),
              ),
            ),
          ),
        ]),
      );

  Widget _addTile({required bool main}) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : addPhotos,
        child: Container(
          decoration: BoxDecoration(
            color: main ? _chip : const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: main ? _blue : const Color(0xFFCBD5E1), width: 1.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
            Icon(main ? Icons.upload_rounded : Icons.add_photo_alternate_outlined, color: main ? _blue : const Color(0xFF94A3B8), size: 24),
            if (main) const Text('Tải ảnh lên', style: TextStyle(color: _blue, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final canAdd = havePhotos + photos.length < maxProjectPhotos;
    return SizedBox(
      height: mq.size.height * .9,
      child: Column(children: [
        // đầu bảng: thanh kéo + tiêu đề + nút đóng
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(editing ? 'Sửa dự án' : 'Đăng tải dự án mới',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: _ink)),
              ),
              Material(
                color: const Color(0xFFF1F5F9),
                shape: const CircleBorder(),
                child: IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close, size: 18, color: Color(0xFF475569)), onPressed: busy ? null : () => Navigator.pop(context)),
              ),
            ]),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _label('Tên dự án', req: true),
              TextField(
                controller: name,
                enabled: !busy,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: _deco('Vd: Nhà phố anh Hưng'),
              ),
              _label('Địa chỉ', req: true),
              Row(spacing: 8, children: [
                _select('Tỉnh / Thành phố', prov, 'Chọn tỉnh', chooseProv),
                _select('Phường / Xã', ward, 'Chọn phường', chooseWard, enabled: prov.isNotEmpty),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: street,
                enabled: !busy,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: _deco('Số nhà, tên đường'),
              ),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(pin != null ? Icons.where_to_vote : Icons.place, size: 14, color: pin != null ? const Color(0xFF16A34A) : _blue),
                ),
                Expanded(
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(
                      preview.isEmpty ? 'Chọn tỉnh, phường và nhập số nhà' : preview,
                      style: const TextStyle(fontSize: 11.5, height: 1.35, color: _slate),
                    ),
                    const Text(' · ', style: TextStyle(fontSize: 11.5, color: _slate)),
                    InkWell(
                      onTap: busy ? null : choosePin,
                      child: Text(
                        pin != null ? 'Đã ghim · sửa' : 'Ghim trên bản đồ',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _blue),
                      ),
                    ),
                  ]),
                ),
              ]),
              _label('Loại công trình'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in projectKinds)
                  ChoiceChip(
                    label: Text(k),
                    selected: kind == k,
                    showCheckmark: false,
                    labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kind == k ? Colors.white : const Color(0xFF334155)),
                    selectedColor: _ink,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: kind == k ? _ink : _line),
                    shape: const StadiumBorder(),
                    onSelected: busy ? null : (on) => setState(() => kind = on ? k : ''),
                  ),
              ]),
              // Tình trạng + Năm hoàn thành (góp ý 24/11): đưa cả dự án đã xong vào hồ sơ năng lực
              _label('Tình trạng'),
              Row(spacing: 8, children: [_statusOpt('hoan_thanh', 'Đã hoàn thành'), _statusOpt('dang_thi_cong', 'Đang thi công')]),
              if (status == 'hoan_thanh') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: year,
                  isExpanded: true,
                  decoration: _deco('').copyWith(labelText: 'Năm hoàn thành', hintText: null),
                  items: [for (var y = DateTime.now().year; y >= DateTime.now().year - 15; y--) DropdownMenuItem(value: y, child: Text('$y'))],
                  onChanged: busy ? null : (v) => setState(() => year = v ?? year),
                ),
              ],
              if (editing && status != 'hoan_thanh') ...[
                _label('Tiến độ: ${progress.round()}%'),
                Slider(value: progress, min: 0, max: 100, divisions: 20, activeColor: _ink, onChanged: busy ? null : (v) => setState(() => progress = v)),
              ],
              _label('Hình ảnh dự án'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4 / 3,
                children: [
                  for (var i = 0; i < photos.length; i++) _photoTile(i),
                  if (canAdd) _addTile(main: photos.isEmpty),
                  if (canAdd && photos.isEmpty) _addTile(main: false),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                havePhotos > 0
                    ? 'Dự án đã có $havePhotos ảnh · thêm tối đa ${maxProjectPhotos - havePhotos} ảnh'
                    : 'Ảnh bìa đặt ở ô đầu tiên · tối đa $maxProjectPhotos ảnh',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
        // nút cố định cuối bảng
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF1F6)))),
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + mq.viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.bad, fontSize: 13)),
            if (pct != null) LinearProgressIndicator(value: pct, color: _blue, backgroundColor: _chip, minHeight: 4),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: busy ? null : save,
                child: busy
                    ? Text(pct != null ? 'Đang tải ảnh ${(pct! * 100).round()}%' : 'Đang lưu…', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))
                    : Text(editing ? 'Lưu dự án' : 'Tạo dự án', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- ghim trên bản đồ

/// Kéo bản đồ cho ghim giữa màn trùng công trình. start: vị trí đã ghim; không có thì tìm theo địa chỉ (query).
class PinPage extends StatefulWidget {
  const PinPage({super.key, this.start, this.query = ''});
  final LatLng? start;
  final String query;
  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  final ctl = MapController();
  late LatLng center = widget.start ?? const LatLng(16.0, 106.2);
  String addr = '';
  bool ready = false, locating = false;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    if (widget.start != null) {
      _reverse();
    } else if (widget.query.trim().isNotEmpty) {
      _search();
    }
  }

  @override
  void dispose() {
    _deb?.cancel();
    super.dispose();
  }

  /// Tìm toạ độ theo địa chỉ đang nhập (API công khai: chỉ địa điểm).
  Future<void> _search() async {
    try {
      final j = await api('/public/geo/search?q=${Uri.encodeQueryComponent(widget.query)}');
      final ps = ((j['places'] as List?) ?? const []).cast<Map>();
      if (ps.isNotEmpty && mounted) {
        final p = LatLng((ps.first['lat'] as num).toDouble(), (ps.first['lng'] as num).toDouble());
        setState(() => center = p);
        if (ready) ctl.move(p, 17);
        _reverse();
      }
    } catch (_) {/* không ra: để người dùng tự kéo */}
  }

  Future<void> _reverse() async {
    try {
      final j = await api('/geocode?lat=${center.latitude}&lng=${center.longitude}');
      if (mounted) setState(() => addr = str(j['address']));
    } catch (_) {
      if (mounted) setState(() => addr = '');
    }
  }

  Future<void> _me() async {
    setState(() => locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        toast('Chưa cho phép vị trí. Kéo bản đồ để ghim tay.');
        return;
      }
      final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 15));
      final l = LatLng(p.latitude, p.longitude);
      ctl.move(l, 18);
      setState(() => center = l);
      _reverse();
    } catch (_) {
      toast('Chưa lấy được vị trí. Kéo bản đồ để ghim tay.');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ghim vị trí công trình')),
        body: Stack(children: [
          FlutterMap(
            mapController: ctl,
            options: MapOptions(
              initialCenter: center,
              initialZoom: widget.start != null ? 17 : 5.5,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () {
                ready = true;
                if (widget.start == null && center != const LatLng(16.0, 106.2)) ctl.move(center, 17);
              },
              onPositionChanged: (cam, byUser) {
                center = cam.center;
                if (byUser) {
                  _deb?.cancel();
                  _deb = Timer(const Duration(milliseconds: 600), _reverse);
                }
              },
            ),
            children: [TileLayer(urlTemplate: '$host/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'vn.com.vuathau', maxNativeZoom: 19)],
          ),
          // ghim cố định giữa bản đồ (mũi ghim chạm đúng tâm)
          const IgnorePointer(
            child: Center(
              child: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_pin, size: 44, color: _red)),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: FloatingActionButton.small(
              heroTag: 'pin-me',
              tooltip: 'Vị trí của tôi',
              backgroundColor: Colors.white,
              onPressed: locating ? null : _me,
              child: locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location, color: _blue),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                  Text(
                    addr.isNotEmpty ? addr : 'Kéo bản đồ để mũi ghim chỉ đúng công trình.',
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF0B1B33), fontWeight: FontWeight.w600),
                  ),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () => Navigator.pop(context, center),
                      child: const Text('Dùng vị trí này', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      );
}
