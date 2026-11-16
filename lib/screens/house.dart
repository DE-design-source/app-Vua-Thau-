// 1 hồ sơ (GET /houses/{id}): phản hồi AI, ảnh, tiền, thông tin công trình, tiến trình, lịch sử. CTV sửa và gửi duyệt ở đây.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../page.dart';
import '../picker.dart';
import '../toast.dart';
import '../ui.dart';
import 'camera.dart';

const _form = ['address', 'floors', 'stage', 'contractor_name', 'contractor_phone'];

class HouseScreen extends StatefulWidget {
  const HouseScreen({super.key, required this.id});
  final int id;
  @override
  State<HouseScreen> createState() => _HouseScreenState();
}

class _HouseScreenState extends State<HouseScreen> with PageData {
  @override
  String get path => '/houses/${widget.id}';

  final ctl = {for (final k in _form) k: TextEditingController()};
  String stage = '';
  final touched = <String>{};
  String busy2 = '';
  bool showLog = false;
  Timer? poll;

  bool get reading => d != null && (d!['house'] as Map)['ai_state'] == 'dang_doc';

  @override
  void initState() {
    super.initState();
    for (final k in _form) {
      ctl[k]!.addListener(() {
        // chỉ đánh dấu khi CTV gõ, không phải khi máy điền
        if (!_filling) touched.add(k);
      });
    }
  }

  bool _filling = false;

  // Dữ liệu mới từ máy chủ: giữ nguyên ô CTV đang gõ dở, ô khác lấy giá trị mới (vd AI vừa đọc xong)
  @override
  void onData(Json j) {
    final h = j['house'] as Map;
    _filling = true;
    for (final k in _form) {
      if (k == 'stage' || touched.contains(k)) continue;
      final v = h[k] == null ? '' : '${h[k]}';
      if (ctl[k]!.text != v) ctl[k]!.text = v;
    }
    _filling = false;
    if (!touched.contains('stage')) stage = str(h['stage']);
    _syncPoll();
    setState(() {});
  }

  // AI đang đọc ảnh: hỏi lại mỗi 3 giây, xong thì tải lại
  void _syncPoll() {
    if (reading && poll == null) {
      poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          final j = await api('/houses/${widget.id}/state');
          if (j['ai_state'] != 'dang_doc') {
            poll?.cancel();
            poll = null;
            load();
          }
        } catch (_) {}
      });
    } else if (!reading) {
      poll?.cancel();
      poll = null;
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// action: luu (lưu nháp) | gui (gửi duyệt)
  Future<void> save(String action) async {
    setState(() => busy2 = action);
    try {
      final j = await put('/houses/${widget.id}', {
        'address': ctl['address']!.text,
        'floors': int.tryParse(ctl['floors']!.text.trim()),
        'stage': stage,
        'contractor_name': ctl['contractor_name']!.text,
        'contractor_phone': ctl['contractor_phone']!.text,
        'submit': action == 'gui',
      });
      toast(msgsOf(j));
      touched.clear();
      await load();
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => busy2 = '');
    }
  }

  Future<void> del(Json p, int n) async {
    if (!await confirm(context, title: 'Xoá ảnh $n khỏi hồ sơ?', ok: 'Xoá')) return;
    try {
      final j = await delete('/houses/${widget.id}/photos/${asInt(p['id'])}');
      toast(msgsOf(j));
      load();
    } catch (e) {
      toast(errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    if (d == null) {
      return Scaffold(body: Column(children: [VtAppBar(title: hsId(widget.id), back: true), Expanded(child: Loading(err: err, retry: load))]));
    }
    final h = (d['house'] as Map).cast<String, dynamic>();
    final ps = (d['photos'] as List?)?.cast<Json>() ?? const <Json>[];
    final editable = d['editable'] == true;
    final todo = (d['todo'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final checklist = (d['checklist'] as List?)?.cast<Map>() ?? const <Map>[];
    final issues = (d['issues'] as List?)?.cast<Map>() ?? const <Map>[];
    final aiTag = (d['ai_fields'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final badFields = (d['bad_fields'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final steps = (d['steps'] as List?)?.cast<Json>() ?? const <Json>[];
    final logs = (d['logs'] as List?)?.cast<Json>() ?? const <Json>[];
    final valid = asInt(d['valid']), pay = asInt(d['pay']);
    final status = str(h['status']);
    // ô thông tin còn thiếu / sai (mục ảnh hiện riêng ở dòng "Cần thêm n ảnh đạt")
    final fieldsTodo = editable
        ? [for (final c in checklist) if (c['ok'] != true && c['key'] != 'anh') str(c['message']).isNotEmpty ? str(c['message']) : str(c['label'])]
        : const <String>[];
    final clean = issues.isEmpty && fieldsTodo.isEmpty;
    final ready = editable && todo.isEmpty && !reading;
    final shown = status == 'tu_choi' ? 0 : editable ? pay : asInt(h['amount']);
    final min = cfg.minPhotos;

    Widget infoField(String k, String label, {String? hint, bool multiline = false, TextInputType? kb}) => Field(
          label: label,
          controller: ctl[k]!,
          hint: hint,
          multiline: multiline,
          keyboardType: kb,
          ai: aiTag.contains(k),
          error: badFields.contains(k) ? 'Số điện thoại chưa đúng: 10 số, bắt đầu bằng 0.' : null,
        );

    return Scaffold(
      body: Column(children: [
        VtAppBar(title: hsId(widget.id), sub: cfg.statusLabel(status), back: true),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: _gap([
                if (status == 'tra_lai' && str(h['note']).isNotEmpty) Note(tone: 'warn', icon: 'undo', title: 'Admin trả lại, bạn cần sửa', text: str(h['note'])),
                if (status == 'tu_choi')
                  Note(tone: 'bad', icon: 'ban', title: 'Hồ sơ bị từ chối', text: str(h['note']).isNotEmpty ? str(h['note']) : 'Không có lý do.'),
                if (status == 'cho_duyet')
                  const Note(tone: 'wait', icon: 'clock', title: 'Đã gửi, đang chờ admin duyệt', text: 'Bạn sẽ thấy kết quả ngay trên trang này.'),

                // ---- Phản hồi AI + luật kiểm ảnh ----
                Box(children: reading
                    ? [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                              Text('AI đang kiểm tra ${ps.length} ảnh…', style: T.secT),
                              const Text('Đọc giờ chụp, địa chỉ, bảng hiệu nhà thầu. Trang tự cập nhật, bạn cứ điền thông tin.', style: T.muted),
                            ]),
                          ),
                        ]),
                      ]
                    : [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                          Avatar(size: 36, color: clean ? C.okBg : C.warnBg, child: Ic(clean ? 'shield' : 'spark', color: clean ? C.ok : C.warn, size: 18)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                              Text(clean ? 'AI kiểm tra: tất cả đều đạt' : 'AI phản hồi: ${issues.length + fieldsTodo.length} điểm cần xem', style: T.secT),
                              Text(
                                '$valid/${ps.length} ảnh đạt · giờ chụp, vị trí, công trình, ảnh trùng${h['ai_state'] == 'loi' ? ' · AI chưa đọc được chữ trên ảnh lần này' : ''}',
                                style: T.muted,
                              ),
                            ]),
                          ),
                        ]),
                        for (final it in issues)
                          _Line(
                              icon: 'image',
                              color: C.bad,
                              text: 'Ảnh ${asInt(it['index'])}: ${((it['problems'] as List?) ?? const []).join('; ')}${editable ? ' — xoá và chụp lại' : ''}'),
                        if (editable && valid < min) _Line(icon: 'x', color: C.bad, text: 'Cần thêm ${min - valid} ảnh đạt (tối thiểu $min)'),
                        for (final t in fieldsTodo) _Line(icon: 'x', color: C.bad, text: t),
                        if (editable && clean) const _Line(icon: 'check', color: C.ok, text: 'Đủ ảnh và thông tin. Bấm Gửi duyệt bên dưới.'),
                      ]),

                // ---- Ảnh ----
                Sec('Ảnh · $valid/${ps.length} đạt', right: 'tối đa ${cfg.maxPhotos}'),
                if (ps.isNotEmpty)
                  PhotoGrid(children: [
                    for (var k = 0; k < ps.length; k++) _cell(ps, k, editable),
                  ]),
                if (editable && ps.length < cfg.maxPhotos) ...[
                  Btn('Chụp thêm bằng camera',
                      icon: 'camera', kind: BtnKind.dark, onPressed: () => push(context, CameraScreen(hid: widget.id, have: ps.length))),
                  PhotoPicker(
                    path: '/houses/${widget.id}/photos',
                    have: ps.length,
                    valid: valid,
                    onUploaded: (_) => load(),
                    title: 'Thêm ảnh có sẵn${valid < min ? ' · cần thêm ${min - valid} ảnh đạt' : ''}',
                  ),
                ],

                // ---- Tiền ----
                Box(children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((editable ? 'Tiền dự kiến' : 'Số tiền hồ sơ').toUpperCase(), style: T.formHead),
                        Text(money(shown), style: T.num.copyWith(fontSize: 24, letterSpacing: -0.5)),
                      ]),
                    ),
                    Text('$valid ảnh đạt\n$min ảnh ${money(cfg.payFor(min))} · ${min + 1}+ ảnh ${money(cfg.payFor(min + 1))}',
                        textAlign: TextAlign.right, style: T.hint.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                  if (editable) Segs(n: valid, total: min + 1),
                ]),

                // ---- Thông tin công trình ----
                const Sec('Thông tin công trình'),
                if (editable)
                  Box(gap: 16, children: [
                    infoField('address', 'Địa chỉ công trình', multiline: true, hint: 'Số nhà, đường, phường/xã, quận/huyện, tỉnh.'),
                    infoField('floors', 'Số tầng', kb: TextInputType.number),
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                      Row(spacing: 6, children: [
                        const Text('Giai đoạn thi công', style: T.label),
                        if (aiTag.contains('stage')) const Pill('AI đoán', tone: 'warn', icon: 'spark'),
                      ]),
                      for (final g in cfg.stages) _stageOpt(g),
                    ]),
                    const Padding(padding: EdgeInsets.only(top: 4), child: Text('NHÀ THẦU (TRÊN BẢNG HIỆU, BẠT CHE)', style: T.formHead)),
                    infoField('contractor_name', 'Tên nhà thầu'),
                    infoField('contractor_phone', 'SĐT nhà thầu', kb: TextInputType.phone),
                  ])
                else
                  Box(gap: 14, children: [
                    _Fact(
                      label: 'Địa chỉ',
                      value: str(h['address']),
                      link: h['lat'] != null ? ('Xem bản đồ', 'https://maps.google.com/?q=${h['lat']},${h['lng']}') : null,
                    ),
                    // Tỉnh mới (34 tỉnh, thành từ 1/7/2025), máy chủ tự gán theo toạ độ / địa chỉ
                    if (str(h['province_name']).isNotEmpty) _Fact(label: 'Tỉnh, thành', value: str(h['province_name'])),
                    _Fact(label: 'Số tầng', value: str(h['floors'])),
                    _Fact(label: 'Giai đoạn', value: str(h['stage'])),
                    _Fact(
                      label: 'Nhà thầu',
                      value: str(h['contractor_name']),
                      link: str(h['contractor_phone']).isNotEmpty ? (str(h['contractor_phone']), 'tel:${str(h['contractor_phone'])}') : null,
                    ),
                  ]),

                // ---- Tiến trình + lịch sử ----
                const Sec('Tiến trình'),
                Box(gap: 0, children: [for (var k = 0; k < steps.length; k++) _step(steps[k], k, steps.length)]),
                if (logs.isNotEmpty)
                  Box(children: [
                    InkWell(
                      onTap: () => setState(() => showLog = !showLog),
                      child: Row(spacing: 6, children: [
                        const Ic('clock', color: C.navy3),
                        Expanded(child: Text('Lịch sử (${logs.length})', style: T.bold)),
                        AnimatedRotation(turns: showLog ? 0.25 : 0, duration: const Duration(milliseconds: 150), child: const Ic('right', color: C.muted, size: 18)),
                      ]),
                    ),
                    if (showLog)
                      for (final l in logs.reversed)
                        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Text(vnTime(str(l['at'])), style: T.mono),
                          Text.rich(TextSpan(style: const TextStyle(color: C.text), children: [
                            TextSpan(text: str(l['action']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            TextSpan(text: ' · ${str(l['user_name'])}'),
                          ])),
                          if (str(l['note']).isNotEmpty) Text(str(l['note']), style: T.muted),
                        ]),
                  ]),
              ]),
            ),
          ),
        ),

        // ---- Thanh hành động ----
        if (editable)
          Container(
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              Row(spacing: 6, children: [
                if (reading)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.warn))
                else
                  Ic(ready ? 'check' : 'alert', color: ready ? C.ok : C.warn, size: 16),
                Expanded(
                  child: Text(
                    reading ? 'AI đang kiểm tra ảnh…' : todo.isNotEmpty ? 'Còn ${todo.length} mục cần bổ sung' : 'Đủ điều kiện · ${money(pay)}',
                    style: TextStyle(color: ready ? C.ok : C.warn, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ]),
              Row(spacing: 8, children: [
                Btn('Lưu nháp', onPressed: () => save('luu'), busy: busy2 == 'luu', disabled: busy2.isNotEmpty),
                Expanded(
                  child: Btn(status == 'tra_lai' ? 'Gửi duyệt lại' : 'Gửi duyệt',
                      icon: 'send', kind: BtnKind.primary, onPressed: () => save('gui'), busy: busy2 == 'gui', disabled: busy2.isNotEmpty || reading),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }

  List<Widget> _gap(List<Widget> xs) => [
        for (var k = 0; k < xs.length; k++) ...[if (k > 0) const SizedBox(height: 12), xs[k]],
      ];

  Widget _cell(List<Json> ps, int k, bool editable) {
    final p = ps[k];
    final problems = (p['problems'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final bad = problems.isNotEmpty;
    return Semantics(
      button: true,
      label: 'Xem ảnh ${k + 1}${bad ? ': ${problems.join(', ')}' : ', đạt'}',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => Lightbox(ps: ps, at: k))),
        child: Container(
          foregroundDecoration: BoxDecoration(border: Border.all(color: bad ? C.bad : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(R.ctl)),
          child: Stack(fit: StackFit.expand, children: [
            NetPhoto.id(asInt(p['id'])),
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: bad ? C.bad : C.ok, borderRadius: BorderRadius.circular(4)),
                alignment: Alignment.center,
                child: Ic(bad ? 'x' : 'check', color: Colors.white, size: 13, stroke: 3),
              ),
            ),
            Positioned(
              left: 32,
              top: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: C.text.withValues(alpha: .72), borderRadius: BorderRadius.circular(3)),
                child: Text((k + 1).toString().padLeft(2, '0'), style: T.mono.copyWith(color: Colors.white, fontSize: 11)),
              ),
            ),
            if (editable) DelBtn(icon: 'trash', label: 'Xoá ảnh ${k + 1}', onTap: () => del(p, k + 1)),
          ]),
        ),
      ),
    );
  }

  Widget _stageOpt(String g) {
    final on = stage == g;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      child: Material(
        color: on ? C.soft : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.ctl), side: BorderSide(color: on ? C.navy : C.field, width: on ? 1.5 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.ctl),
          onTap: () => setState(() {
            stage = g;
            touched.add('stage');
          }),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(spacing: 10, children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? C.navy : C.placeholder, width: 2)),
                alignment: Alignment.center,
                child: on ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: C.navy, shape: BoxShape.circle)) : null,
              ),
              Expanded(child: Text(g, style: T.body)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _step(Json x, int k, int n) {
    final state = str(x['state']);
    final col = switch (state) { 'done' => C.ok, 'current' => C.amber, 'bad' => C.bad, _ => C.field };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Column(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: state == 'todo' ? Colors.white : col, borderRadius: BorderRadius.circular(R.ctl), border: Border.all(color: col, width: 1.5)),
            alignment: Alignment.center,
            child: state == 'done'
                ? const Ic('check', color: Colors.white, size: 15, stroke: 3)
                : state == 'bad'
                    ? const Ic('x', color: Colors.white, size: 15, stroke: 3)
                    : Text('0${k + 1}', style: T.mono.copyWith(fontWeight: FontWeight.w600, color: state == 'current' ? C.navy : C.subtle)),
          ),
          if (k < n - 1) Expanded(child: Container(width: 1.5, constraints: const BoxConstraints(minHeight: 16), color: state == 'done' ? C.ok : C.line)),
        ]),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(str(x['title']), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: state == 'todo' ? C.subtle : C.text)),
              Text('${str(x['who'])}${str(x['at']).isNotEmpty ? ' · ${vnTime(str(x['at']))}' : ''}', style: T.muted),
              if (str(x['hint']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(str(x['hint']), style: const TextStyle(color: C.text, fontSize: 14))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});
  final String icon, text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Ic(icon, color: color, size: 18),
        Expanded(child: Text(text, style: const TextStyle(color: C.text, fontSize: 14, height: 1.4))),
      ]);
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.link});
  final String label, value;
  final (String, String)? link;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text(label.toUpperCase(), style: T.formHead),
        Text(value.isNotEmpty ? value : '—', style: T.body),
        if (link != null)
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(link!.$2), mode: LaunchMode.externalApplication),
            child: Text(link!.$1, style: const TextStyle(color: C.navy3, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
      ]);
}

/// Xem ảnh lớn, vuốt ngang qua ảnh khác, phóng to được, kèm giờ chụp, vị trí, lỗi.
class Lightbox extends StatefulWidget {
  const Lightbox({super.key, required this.ps, required this.at});
  final List<Json> ps;
  final int at;
  @override
  State<Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<Lightbox> {
  late int cur = widget.at;
  late final page = PageController(initialPage: widget.at);

  @override
  void dispose() {
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.ps[cur];
    final t = str(p['exif_time']).isNotEmpty ? str(p['exif_time']) : str(p['ai_time']);
    final problems = (p['problems'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final lat = p['lat'] as num?, lng = p['lng'] as num?;
    final where = str(p['address']).isNotEmpty
        ? str(p['address'])
        : lat != null && lng != null
            ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
            : 'Không có vị trí';
    const ok = Color(0xFF6CE9A6), bad = Color(0xFFFDA29B);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(children: [
                Expanded(child: Text('Ảnh ${cur + 1} / ${widget.ps.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))),
                IconButton(tooltip: 'Đóng', onPressed: () => Navigator.pop(context), icon: const Ic('x', color: Colors.white, size: 26)),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: page,
                itemCount: widget.ps.length,
                onPageChanged: (i) => setState(() => cur = i),
                itemBuilder: (context, i) => InteractiveViewer(maxScale: 5, child: NetPhoto.id(asInt(widget.ps[i]['id']), fit: BoxFit.contain)),
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.black.withValues(alpha: .85),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Row(spacing: 6, children: [
                  const Ic('clock', color: Colors.white, size: 16),
                  Text(t.isNotEmpty ? vnTime(t) : 'Không đọc được giờ chụp', style: const TextStyle(color: Colors.white)),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                  const Ic('pin', color: Colors.white, size: 16),
                  Expanded(child: Text(where, style: const TextStyle(color: Colors.white))),
                ]),
                if (problems.isNotEmpty)
                  for (final x in problems)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                      const Ic('x', color: bad, size: 16),
                      Expanded(child: Text(x, style: const TextStyle(color: bad))),
                    ])
                else
                  const Row(spacing: 6, children: [Ic('check', color: ok, size: 16), Text('Ảnh đạt', style: TextStyle(color: ok))]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
