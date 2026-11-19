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
import '../video.dart';
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
  int jPick = -1; // mốc đang xem nhật ký ảnh (-1: chưa chọn)
  final touched = <String>{};
  String busy2 = '';
  bool showLog = false;
  bool allPhotos = false;
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
    final vs = (d['videos'] as List?)?.cast<Json>() ?? const <Json>[];
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

    final addr = str(h['address']);
    final province = str(h['province_name']);
    final showGrid = allPhotos || (editable && issues.isNotEmpty);

    return Scaffold(
      body: Column(children: [
        VtAppBar(title: 'Chi tiết hồ sơ', sub: hsId(widget.id), back: true),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: _gap([
                // ---- Đầu trang: mã, trạng thái, AI, địa chỉ, giai đoạn ----
                Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(hsId(widget.id), style: T.num.copyWith(fontSize: 13, color: C.muted)),
                    StatusBadge(status),
                    if (reading)
                      const Pill('AI đang đọc ảnh', tone: 'wait', icon: 'spark')
                    else if (clean && valid > 0)
                      const Pill('AI đã xác minh', tone: 'ok', icon: 'shield'),
                  ]),
                  Text(addr.isNotEmpty ? addr : 'Chưa có địa chỉ công trình',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.3, color: addr.isNotEmpty ? C.text : C.subtle)),
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (stage.isNotEmpty) Pill(stage, tone: 'done', icon: 'building'),
                    if (province.isNotEmpty) Text(province, style: T.muted),
                    if (str(h['floors']).isNotEmpty && str(h['floors']) != '0') Text('· ${str(h['floors'])} tầng', style: T.muted),
                  ]),
                ]),

                if (status == 'tra_lai' && str(h['note']).isNotEmpty) Note(tone: 'warn', icon: 'undo', title: 'Admin trả lại, bạn cần sửa', text: str(h['note'])),
                if (status == 'tu_choi')
                  Note(tone: 'bad', icon: 'ban', title: 'Hồ sơ bị từ chối', text: str(h['note']).isNotEmpty ? str(h['note']) : 'Không có lý do.'),
                if (status == 'cho_duyet')
                  const Note(tone: 'wait', icon: 'clock', title: 'Đã gửi, đang chờ admin duyệt', text: 'Bạn sẽ thấy kết quả ngay trên trang này.'),

                // ---- Ảnh: khối ghép + xem tất cả ----
                if (ps.isNotEmpty) _mosaic(ps, showGrid),
                if (showGrid) ...[
                  Sec('Ảnh · $valid/${ps.length} đạt', right: 'tối đa ${cfg.maxPhotos}'),
                  PhotoGrid(children: [
                    for (var k = 0; k < ps.length; k++) _cell(ps, k, editable),
                  ]),
                ],
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

                // ---- Video công trình (không qua AI; có video được cộng thưởng cfg.videoBonus) ----
                if (editable || vs.isNotEmpty) VideoSection(hid: widget.id, videos: vs, editable: editable, onChanged: load),

                // ---- Phản hồi AI + luật kiểm ảnh ----
                Box(children: reading
                    ? [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                              Text('AI đang kiểm tra ${ps.length} ảnh…', style: T.bold),
                              const Text('Đọc giờ chụp, địa chỉ, bảng hiệu nhà thầu. Trang tự cập nhật, bạn cứ điền thông tin.', style: T.muted),
                            ]),
                          ),
                        ]),
                      ]
                    : [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                          Avatar(size: 36, color: clean ? C.okBg : C.waitBg, child: Ic(clean ? 'shield' : 'spark', color: clean ? C.ok : C.alert, size: 18)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                              Text(clean ? 'AI kiểm tra: tất cả đều đạt' : 'AI phản hồi: ${issues.length + fieldsTodo.length} điểm cần xem', style: T.bold),
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

                // ---- Tiến độ thi công: 8 mốc ----
                if (cfg.stages.isNotEmpty) _milestones(),

                // ---- Tiền ----
                FieldBox(firstShaded: true, rows: [
                  [
                    FieldCell(editable ? 'Tiền dự kiến' : 'Số tiền hồ sơ', '',
                        child: Text(money(shown), style: T.num.copyWith(fontSize: 24, letterSpacing: -0.5))),
                  ],
                  [
                    FieldCell('Ảnh đạt', '$valid / ${ps.length}'),
                    FieldCell('$min ảnh', money(cfg.payFor(min))),
                    FieldCell('${min + 1}+ ảnh', money(cfg.payFor(min + 1))),
                  ],
                  if (cfg.videoBonus > 0)
                    [
                      FieldCell('Thưởng video', vs.isNotEmpty ? '+${money(cfg.videoBonus)} (đã có video)' : '+${money(cfg.videoBonus)} nếu thêm video'),
                    ],
                ]),
                if (editable) Segs(n: valid, total: min + 1),

                // ---- Tiến trình duyệt ----
                if (steps.isNotEmpty) ...[
                  const Sec('Tiến trình duyệt'),
                  Box(gap: 14, children: [
                    Row(spacing: 4, children: [
                      for (final x in steps)
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: switch (str(x['state'])) { 'done' => C.ok, 'current' => C.blue, 'bad' => C.bad, _ => C.line },
                            ),
                          ),
                        ),
                    ]),
                    Column(children: [for (var k = 0; k < steps.length; k++) _step(steps[k], k, steps.length)]),
                  ]),
                ],

                // ---- Thông tin công trình ----
                const Sec('Thông tin công trình'),
                if (editable)
                  Box(gap: 16, children: [
                    infoField('address', 'Địa chỉ công trình', multiline: true, hint: 'Số nhà, đường, phường/xã, quận/huyện, tỉnh.'),
                    infoField('floors', 'Số tầng', kb: TextInputType.number),
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                      Row(spacing: 6, children: [
                        const Text('GIAI ĐOẠN THI CÔNG', style: T.cap),
                        if (aiTag.contains('stage')) const Pill('AI đoán', tone: 'wait', icon: 'spark'),
                      ]),
                      for (final g in cfg.stages) _stageOpt(g),
                    ]),
                    const Padding(padding: EdgeInsets.only(top: 4), child: Text('NHÀ THẦU (TRÊN BẢNG HIỆU, BẠT CHE)', style: T.formHead)),
                    infoField('contractor_name', 'Tên nhà thầu'),
                    infoField('contractor_phone', 'SĐT nhà thầu', kb: TextInputType.phone),
                  ])
                else
                  FieldBox(rows: [
                    [
                      _Fact(
                        label: 'Địa chỉ',
                        value: addr,
                        link: h['lat'] != null ? ('Xem Google Maps', gmapUrl(h['lat'], h['lng'])) : null,
                        copy: h['lat'] != null ? gmapUrl(h['lat'], h['lng']) : null,
                      ),
                    ],
                    // Tỉnh mới (34 tỉnh, thành từ 1/7/2025), máy chủ tự gán theo toạ độ / địa chỉ
                    if (province.isNotEmpty) [FieldCell('Tỉnh, thành', province)],
                    [FieldCell('Số tầng', str(h['floors'])), FieldCell('Giai đoạn', str(h['stage']))],
                    [
                      _Fact(
                        label: 'Nhà thầu',
                        value: str(h['contractor_name']),
                        link: str(h['contractor_phone']).isNotEmpty ? (str(h['contractor_phone']), 'tel:${str(h['contractor_phone'])}') : null,
                      ),
                    ],
                  ]),

                // ---- Lịch sử ----
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
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.alert))
                else
                  Ic(ready ? 'check' : 'alert', color: ready ? C.ok : C.alert, size: 16),
                Expanded(
                  child: Text(
                    reading ? 'AI đang kiểm tra ảnh…' : todo.isNotEmpty ? 'Còn ${todo.length} mục cần bổ sung' : 'Đủ điều kiện · ${money(pay)}',
                    style: TextStyle(color: ready ? C.ok : C.alert, fontWeight: FontWeight.w600, fontSize: 14),
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

  void _open(List<Json> ps, int k) =>
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => Lightbox(ps: ps, at: k)));

  /// Ảnh ghép kiểu Airbnb: 1 ảnh lớn + tối đa 4 ảnh nhỏ, nút "Hiển thị tất cả" ở góc.
  Widget _mosaic(List<Json> ps, bool open) {
    final n = ps.length;
    Widget tile(int k) => Semantics(
          button: true,
          label: 'Xem ảnh ${k + 1}',
          child: GestureDetector(onTap: () => _open(ps, k), child: NetPhoto.id(asInt(ps[k]['id']))),
        );
    Widget col(List<int> ks) => Column(spacing: 4, crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final k in ks) Expanded(child: tile(k))]);
    final Widget body = switch (n) {
      1 => tile(0),
      2 => Row(spacing: 4, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: tile(0)), Expanded(child: tile(1))]),
      3 || 4 => Row(spacing: 4, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 2, child: tile(0)),
          Expanded(child: col([for (var k = 1; k < n; k++) k])),
        ]),
      _ => Row(spacing: 4, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 2, child: tile(0)),
          Expanded(child: col([1, 3])),
          Expanded(child: col([2, 4])),
        ]),
    };
    return SizedBox(
      height: 232,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(borderRadius: BorderRadius.circular(R.card), child: body),
        Positioned(
          right: 10,
          bottom: 10,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.ctl), side: const BorderSide(color: C.text)),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.ctl),
              onTap: () => setState(() => allPhotos = !open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  const Ic('image', size: 15),
                  Text(open ? 'Thu gọn ảnh' : 'Hiển thị tất cả $n ảnh', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// Tiến độ thi công: các mốc (cfg.stages, 8 bước) nối bằng vạch; mốc đã qua tô navy, mốc hiện tại viền xanh.
  Widget _milestones() {
    final gs = cfg.stages;
    final at = gs.indexOf(stage);
    // nhật ký: bộ ảnh đã duyệt (của bạn) ở cùng công trình, theo giai đoạn
    final journal = (d?['journal'] as List?)?.cast<Json>() ?? const <Json>[];
    List<Json> setsOf(int k) => [for (final j in journal) if (str(j['stage']) == gs[k] && (j['photos'] as List?)?.isNotEmpty == true) j];
    final withSets = [for (var k = 0; k < gs.length; k++) if (setsOf(k).isNotEmpty) k];
    void pick(int k) => setState(() => jPick = jPick == k ? -1 : k);
    Widget dot(int k) {
      final done = k < at, cur = k == at;
      final has = withSets.contains(k);
      final circle = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? C.navy3 : Colors.white,
            border: Border.all(color: done ? C.navy3 : cur ? C.blue : C.dot, width: cur ? 2.5 : 1.5),
          ),
          alignment: Alignment.center,
          child: done
              ? const Ic('check', color: Colors.white, size: 12, stroke: 3)
              : Text('${k + 1}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: cur ? C.blue : C.subtle)),
        );
      return Tooltip(
        message: gs[k],
        child: GestureDetector(
          onTap: has ? () => pick(k) : null,
          behavior: HitTestBehavior.opaque,
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            Container(
              decoration: jPick == k ? BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: C.blue.withValues(alpha: .25), spreadRadius: 3)]) : null,
              child: circle,
            ),
            // chấm nhỏ: mốc có bộ ảnh xem lại được
            Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: has ? C.blue : Colors.transparent)),
          ]),
        ),
      );
    }

    return Box(raised: true, gap: 14, children: [
      Row(children: [
        const Expanded(child: Text('Tiến độ thi công', style: T.bold)),
        Text(at >= 0 ? 'Mốc ${at + 1}/${gs.length}' : 'Chưa chọn giai đoạn', style: T.hint),
      ]),
      Semantics(
        label: at >= 0 ? 'Giai đoạn ${at + 1} trên ${gs.length}: ${gs[at]}' : 'Chưa chọn giai đoạn',
        child: Row(children: [
          for (var k = 0; k < gs.length; k++) ...[
            if (k > 0) Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 9), child: Container(height: 2, color: k <= at ? C.navy3 : C.line))),
            dot(k),
          ],
        ]),
      ),
      if (at >= 0)
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(gs[at], style: T.bold),
            Pill(at == gs.length - 1 ? 'Đã bàn giao' : 'Đang thi công', tone: at == gs.length - 1 ? 'ok' : 'done'),
          ]),
          if (at < gs.length - 1) Text('Tiếp theo: ${gs[at + 1]}', style: T.muted),
        ]),
      // ---- nhật ký ảnh: các bước có bộ ảnh đã duyệt ----
      if (withSets.isNotEmpty) ...[
        const Divider(height: 1, color: C.line),
        Text('XEM ẢNH NHẬT KÝ CÔNG TRÌNH', style: T.cap),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in withSets)
            Semantics(
              button: true,
              selected: jPick == k,
              child: Material(
                color: jPick == k ? C.text : Colors.white,
                shape: StadiumBorder(side: BorderSide(color: jPick == k ? C.text : C.line2)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => pick(k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text('${k + 1}. ${gs[k]} · ${setsOf(k).length} bộ',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: jPick == k ? Colors.white : C.text)),
                  ),
                ),
              ),
            ),
        ]),
        if (jPick >= 0 && jPick < gs.length)
          for (final j in setsOf(jPick)) _journalSet(j),
      ],
    ]);
  }

  /// 1 bộ ảnh trong nhật ký: ngày gửi (+ "hồ sơ này"), ảnh nhỏ cuộn ngang, chạm để xem lớn.
  Widget _journalSet(Json j) {
    final ps = [for (final id in (j['photos'] as List)) <String, dynamic>{'id': id}];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Row(spacing: 8, children: [
        Expanded(child: Text('Gửi ${vnDate(str(j['at']))} · ${ps.length} ảnh', style: T.bold.copyWith(fontSize: 14))),
        if (j['self'] == true) const Pill('Hồ sơ này', tone: 'done') else Text(hsId(j['house_id']), style: T.hint),
      ]),
      SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ps.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, k) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => Lightbox(ps: ps, at: k))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(R.ctl),
              child: SizedBox(width: 84, height: 84, child: NetPhoto.id(asInt(ps[k]['id']))),
            ),
          ),
        ),
      ),
    ]);
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
        color: on ? C.blueBg : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.ctl), side: BorderSide(color: on ? C.blue : C.field, width: on ? 1.5 : 1)),
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
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? C.blue : C.placeholder, width: 2)),
                alignment: Alignment.center,
                child: on ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: C.blue, shape: BoxShape.circle)) : null,
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
    final col = switch (state) { 'done' => C.ok, 'current' => C.blue, 'bad' => C.bad, _ => C.dot };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Column(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: state == 'done' || state == 'bad' ? col : Colors.white, shape: BoxShape.circle, border: Border.all(color: col, width: state == 'current' ? 2.5 : 1.5)),
            alignment: Alignment.center,
            child: state == 'done'
                ? const Ic('check', color: Colors.white, size: 15, stroke: 3)
                : state == 'bad'
                    ? const Ic('x', color: Colors.white, size: 15, stroke: 3)
                    : Text('${k + 1}', style: T.num.copyWith(fontSize: 12, color: state == 'current' ? C.blue : C.subtle)),
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

/// Link Google Maps của 1 toạ độ (không cần key; điện thoại có app Google Maps thì mở app).
String gmapUrl(Object? lat, Object? lng) => 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.link, this.copy});
  final String label, value;
  final (String, String)? link;

  /// Có: thêm nút "Chép link" bên cạnh link (để gửi qua Zalo...)
  final String? copy;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text(label.toUpperCase(), style: T.cap),
        Text(value.isNotEmpty ? value : '—', style: T.body),
        if (link != null)
          Wrap(spacing: 16, children: [
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(link!.$2), mode: LaunchMode.externalApplication),
              child: Text(link!.$1, style: const TextStyle(color: C.blue, fontWeight: FontWeight.w600, fontSize: 15, decoration: TextDecoration.underline)),
            ),
            if (copy != null)
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: copy!));
                  toast('Đã chép link Google Maps, dán vào Zalo để gửi');
                },
                child: const Text('Chép link', style: TextStyle(color: C.blue, fontWeight: FontWeight.w600, fontSize: 15, decoration: TextDecoration.underline)),
              ),
          ]),
      ]));
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
