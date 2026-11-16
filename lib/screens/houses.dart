// Hồ sơ của tôi (như /cua-toi): tiền, tiến độ gom 5 hồ sơ, lọc theo trạng thái, danh sách hồ sơ.
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
  String get path => '/cua-toi${loc.isNotEmpty ? '?loc=$loc' : ''}';
  @override
  bool get watchRoute => false;

  void setLoc(String k) {
    setState(() => loc = k);
    load();
  }

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    final user = d?['user'] as Json?;
    final name = user != null ? str(user['name']).trim().split(RegExp(r'\s+')).last : '';
    final rows = (d?['rows'] as List?)?.cast<Json>() ?? const <Json>[];

    return Column(children: [
      VtAppBar(title: name.isNotEmpty ? 'Chào $name' : 'Hồ sơ của tôi', sub: 'Cộng tác viên'),
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
                              onTap: () => tabIndex.value = 1,
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
    final m = d['m'] as Json;
    final approved = asInt(m['approved']);
    final count = (d['count'] as Map?)?.map((k, v) => MapEntry('$k', asInt(v))) ?? const <String, int>{};
    final tabs = (d['tabs'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final canLam = count['can_lam'] ?? 0;
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
                Text('$approved/${cfg.payMin}', style: T.muted),
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
                for (final e in tabs.entries)
                  if (e.key.isEmpty || (count[e.key] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _chip(e.key, str((e.value as List).first), count[e.key] ?? 0),
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
        shape: StadiumBorder(side: BorderSide(color: on ? C.navy : C.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setLoc(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: on ? Colors.white : C.text)),
              Text('$n', style: TextStyle(fontWeight: FontWeight.w700, color: on ? C.amber : C.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(Json d, List<Json> rows, int index) {
    final r = rows[index];
    final id = asInt(r['id']);
    final st = (d['stats'] as Map?)?['$id'] as Map? ?? const {};
    final n = asInt(st['n']), valid = asInt(st['valid']), cover = st['cover'];
    final bad = n - valid;
    final status = str(r['status']);
    final first = index == 0, last = index == rows.length - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 12 : 0, 16, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(first ? 12 : 0), bottom: Radius.circular(last ? 12 : 0)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => push(context, HouseScreen(id: id)),
          child: Container(
            decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
            padding: const EdgeInsets.all(14),
            child: Row(spacing: 12, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: cover != null ? NetPhoto.id(asInt(cover), width: 64, height: 64) : Container(color: C.line, alignment: Alignment.center, child: const Ic('image', color: C.muted)),
                ),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                  Text(str(r['address']).isNotEmpty ? str(r['address']) : 'Hồ sơ #$id',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text)),
                  Text('#$id · $valid/$n ảnh đạt · ${vnDate(str(r['created_at']))}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.muted),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    StatusBadge(status),
                    if (bad > 0 && const ['nhap', 'tra_lai', 'cho_duyet'].contains(status)) Pill('$bad ảnh lỗi', tone: 'bad'),
                  ]),
                ]),
              ),
              if (asInt(r['amount']) > 0) Text(money(asInt(r['amount'])), style: const TextStyle(fontWeight: FontWeight.w700, color: C.text)),
              const Ic('right', color: C.muted, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
