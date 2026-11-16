// Hồ sơ của tôi (GET /ctv/home): tiền, tiến độ gom 5 hồ sơ, lọc theo trạng thái, danh sách hồ sơ.
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
                  padding: const EdgeInsets.only(bottom: 24),
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
    final tabs = (d['tabs'] as List?)?.cast<Map>() ?? const <Map>[];
    final canLam = asInt(tabs.where((t) => t['key'] == 'can_lam').firstOrNull?['count']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MoneyHero(label: 'Đã nhận', amount: asInt(m['paid']), stats: [('Chờ thanh toán', asInt(m['owed'])), ('Đang chờ duyệt', asInt(m['reviewing']))]),
      Lift(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Box(onTap: () => setLoc('da_duyet'), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                Expanded(
                  child: Text(
                    approved >= cfg.payMin ? 'Đủ ${cfg.payMin} hồ sơ, sắp được chuyển khoản' : 'Còn ${cfg.payMin - approved} hồ sơ nữa là được thanh toán',
                    style: T.bold,
                  ),
                ),
                Text('$approved/${cfg.payMin}', style: T.num.copyWith(color: C.muted, fontSize: 14)),
              ]),
              Segs(n: approved, total: cfg.payMin),
              Text('Kế toán chuyển khoản gộp khi bạn có từ ${cfg.payMin} hồ sơ đã duyệt.', style: T.muted),
            ]),
            if (canLam > 0)
              Note(
                tone: 'warn',
                icon: 'alert',
                title: '$canLam hồ sơ cần bạn xử lý',
                text: 'Bổ sung theo phản hồi của AI hoặc admin rồi gửi lại.',
                onTap: () => setLoc('can_lam'),
              ),
            SizedBox(
              height: 36,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final t in tabs)
                  if (str(t['key']).isEmpty || asInt(t['count']) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _chip(str(t['key']), str(t['label']), asInt(t['count'])),
                    ),
              ]),
            ),
          ]),
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
        color: on ? C.navy : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.ctl), side: BorderSide(color: on ? C.navy : C.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.ctl),
          onTap: () => setLoc(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: on ? Colors.white : C.text)),
              Text('$n', style: T.num.copyWith(fontSize: 12.5, color: on ? C.amber : C.subtle)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(Json d, List<Json> rows, int index) {
    final r = rows[index];
    final id = asInt(r['id']);
    final n = asInt(r['photos_total']), valid = asInt(r['photos_valid']), cover = r['cover_id'];
    final bad = n - valid;
    final status = str(r['status']);
    final first = index == 0, last = index == rows.length - 1;
    const side = BorderSide(color: C.line);
    // Cả danh sách là 1 khung viền 1px, các dòng ngăn bằng vạch mảnh
    return Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 4 : 0, 16, 0),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () => push(context, HouseScreen(id: id)),
          child: Container(
            decoration: BoxDecoration(border: Border(top: side, bottom: last ? side : BorderSide.none, left: side, right: side)),
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(spacing: 12, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(R.ctl),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: cover != null
                      ? NetPhoto.id(asInt(cover), width: 56, height: 56)
                      : Container(color: C.soft, alignment: Alignment.center, child: const Ic('image', color: C.subtle, size: 18)),
                ),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                  Row(spacing: 8, children: [
                    Text(hsId(id), style: T.mono),
                    Text('$valid/$n ảnh đạt · ${vnDate(str(r['created_at']))}', style: T.hint.copyWith(color: C.subtle, fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                  Text(str(r['address']).isNotEmpty ? str(r['address']) : 'Chưa có địa chỉ',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: C.text)),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    StatusBadge(status),
                    if (r['vip'] == true) const Pill('VIP · chụp đầu tiên', tone: 'warn'),
                    if (bad > 0 && const ['nhap', 'tra_lai', 'cho_duyet'].contains(status)) Pill('$bad ảnh lỗi', tone: 'bad'),
                  ]),
                ]),
              ),
              if (asInt(r['amount']) > 0) Text(money(asInt(r['amount'])), style: T.num.copyWith(fontSize: 14)),
              const Ic('right', color: C.subtle, size: 16),
            ]),
          ),
        ),
      ),
    );
  }
}
