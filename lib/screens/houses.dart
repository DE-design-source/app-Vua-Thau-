// Hồ sơ của tôi (GET /ctv/home), hệ thiết kế 18/11/2026: thẻ tiền + tiến độ gom hồ sơ, lọc viên tròn, thẻ hồ sơ có ảnh bìa lớn.
import 'package:flutter/material.dart';

import '../api.dart';
import '../page.dart';
import '../ui.dart';
import 'home_shell.dart';
import 'house.dart';

class HousesScreen extends StatefulWidget {
  const HousesScreen({super.key});
  @override
  State<HousesScreen> createState() => _HousesScreenState();
}

class _HousesScreenState extends State<HousesScreen> with PageData {
  String loc = '';
  @override
  String get path => '/ctv/home${loc.isNotEmpty ? '?tab=$loc' : ''}';
  @override
  bool get watchRoute => false;

  @override
  void initState() {
    super.initState();
    me.addListener(_tick);
    if (me.value == null) loadMe(); // mở lại app: lấy tên cho lời chào
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    me.removeListener(_tick);
    super.dispose();
  }

  @override
  void onData(Json j) {
    if (j['todo'] is num) badge.value = (j['todo'] as num).toInt();
  }

  void setLoc(String k) {
    setState(() => loc = k);
    load();
  }

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    final user = me.value;
    final name = user != null ? str(user['name']).trim().split(RegExp(r'\s+')).last : '';
    final rows = (d?['rows'] as List?)?.cast<Json>() ?? const <Json>[];

    return Column(children: [
      VtAppBar(title: name.isNotEmpty ? 'Chào $name' : 'Hồ sơ của tôi', sub: 'Cộng tác viên', right: const TopActions()),
      Expanded(
        child: RefreshIndicator(
          onRefresh: load,
          child: d == null
              ? ListView(children: [Loading(err: err, retry: load)])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: 1 + (rows.isEmpty ? 1 : rows.length),
                  itemBuilder: (context, i) {
                    if (i == 0) return _head(d);
                    if (rows.isEmpty) {
                      return asInt(d['total']) > 0
                          ? const Empty(icon: 'inbox', title: 'Không có hồ sơ nào ở mục này', text: 'Chọn mục khác ở trên để xem.')
                          : Empty(
                              icon: 'building',
                              title: 'Nộp hồ sơ đầu tiên',
                              text: 'Chụp công trình đang xây (ít nhất ${cfg.minPhotos} ảnh) rồi tải lên.',
                              cta: 'Nộp ảnh công trình',
                              onTap: () => tabIndex.value = tabShoot,
                            );
                    }
                    return _row(d, rows, i - 1);
                  },
                ),
        ),
      ),
    ]);
  }

  Widget _head(Json d) {
    final m = (d['money'] as Map?) ?? const {};
    final approved = asInt(m['approved']);
    final full = approved >= cfg.payMin;
    final tabs = (d['tabs'] as List?)?.cast<Map>() ?? const <Map>[];
    final canLam = asInt(tabs.where((t) => t['key'] == 'can_lam').firstOrNull?['count']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          // ---- thẻ tiền (như màn Thu nhập) ----
          Box(raised: true, padding: const EdgeInsets.all(20), gap: 14, onTap: () => setLoc('da_duyet'), children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
              Text(money(asInt(m['paid'])),
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600, color: C.text, decoration: TextDecoration.underline, letterSpacing: -0.5, height: 1.2)),
              const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('đã nhận', style: TextStyle(fontSize: 16, color: C.text))),
            ]),
            FieldBox(radius: 8, rows: [
              [FieldCell('Chờ thanh toán', money(asInt(m['owed']))), FieldCell('Đang chờ duyệt', money(asInt(m['reviewing'])))],
            ]),
            Row(children: [
              Expanded(child: Text('Lần thanh toán tới', style: T.cap)),
              Text('$approved/${cfg.payMin} hồ sơ', style: T.num.copyWith(fontSize: 13, color: full ? C.ok : C.muted)),
            ]),
            Segs(n: approved, total: cfg.payMin),
            Text(
              full ? 'Đủ ${cfg.payMin} hồ sơ, sắp được chuyển khoản.' : 'Còn ${cfg.payMin - approved} hồ sơ được duyệt nữa là kế toán chuyển khoản.',
              style: T.muted,
            ),
          ]),
          if (canLam > 0)
            Note(
              tone: 'warn',
              icon: 'alert',
              title: '$canLam hồ sơ cần bạn xử lý',
              text: 'Bổ sung theo phản hồi của AI hoặc admin rồi gửi lại.',
              onTap: () => setLoc('can_lam'),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Expanded(child: Text('Hồ sơ của bạn', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.3))),
              Text('${asInt(d['total'])} hồ sơ', style: T.hint),
            ]),
          ),
        ]),
      ),
      // ---- lọc: viên tròn cuộn ngang ----
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          children: [
            for (final t in tabs)
              if (str(t['key']).isEmpty || asInt(t['count']) > 0)
                Padding(padding: const EdgeInsets.only(right: 8), child: _chip(str(t['key']), str(t['label']), asInt(t['count']))),
          ],
        ),
      ),
    ]);
  }

  Widget _chip(String k, String label, int n) {
    final on = loc == k;
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? C.text : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: on ? C.text : C.line2)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setLoc(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? Colors.white : C.text)),
              Text('$n', style: T.num.copyWith(fontSize: 12.5, color: on ? Colors.white70 : C.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  /// 1 hồ sơ kiểu thẻ Airbnb: ảnh bìa lớn (nhãn trạng thái, VIP, ảnh lỗi đè lên), dưới là địa chỉ, mã + ảnh đạt + ngày, giai đoạn, tiền.
  Widget _row(Json d, List<Json> rows, int index) {
    final r = rows[index];
    final id = asInt(r['id']);
    final n = asInt(r['photos_total']), valid = asInt(r['photos_valid']), cover = r['cover_id'];
    final bad = n - valid;
    final status = str(r['status']);
    final stage = str(r['stage']);
    final amount = asInt(r['amount']);
    final (fg, _) = tones[cfg.statusTone(status)] ?? tones['draft']!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Semantics(
        button: true,
        label: 'Hồ sơ ${hsId(id)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(R.card),
          onTap: () => push(context, HouseScreen(id: id)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(R.card),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(fit: StackFit.expand, children: [
                  if (cover != null)
                    NetPhoto.id(asInt(cover))
                  else
                    Container(color: C.soft, alignment: Alignment.center, child: const Ic('image', color: C.subtle, size: 28)),
                  // trạng thái: viên trắng, chấm màu
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), boxShadow: const [
                        BoxShadow(color: Color(0x26000000), blurRadius: 6, offset: Offset(0, 2)),
                      ]),
                      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
                        Text(cfg.statusLabel(status), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.text)),
                      ]),
                    ),
                  ),
                  if (r['vip'] == true || (bad > 0 && const ['nhap', 'tra_lai', 'cho_duyet'].contains(status)))
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Row(spacing: 6, children: [
                        if (bad > 0 && const ['nhap', 'tra_lai', 'cho_duyet'].contains(status)) Pill('$bad ảnh lỗi', tone: 'bad'),
                        if (r['vip'] == true) const Pill('VIP', tone: 'vip', icon: 'bolt'),
                      ]),
                    ),
                ]),
              ),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                  Text(str(r['address']).isNotEmpty ? str(r['address']) : 'Chưa có địa chỉ',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: C.text, height: 1.3)),
                  Text('${hsId(id)} · $valid/$n ảnh đạt · ${vnDate(str(r['created_at']))}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: T.muted.copyWith(fontSize: 13.5, fontFeatures: const [FontFeature.tabularFigures()])),
                  if (stage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.blue, shape: BoxShape.circle)),
                        Flexible(
                            child: Text(stage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.navy3))),
                      ]),
                    ),
                ]),
              ),
              if (amount > 0)
                Text(money(amount), style: T.num.copyWith(fontSize: 15, decoration: TextDecoration.underline)),
            ]),
          ]),
        ),
      ),
    );
  }
}
