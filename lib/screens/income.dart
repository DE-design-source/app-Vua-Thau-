// Thu nhập (như /thu-nhap): tổng tiền, lần thanh toán tới, tài khoản nhận tiền, lịch sử nhận tiền.
import 'package:flutter/material.dart';

import '../api.dart';
import '../page.dart';
import '../ui.dart';
import 'home_shell.dart';
import 'payment.dart';

class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});
  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> with PageData {
  @override
  String get path => '/thu-nhap';
  @override
  bool get watchRoute => false;

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    return Column(children: [
      const VtAppBar(title: 'Thu nhập', sub: 'Tiền nghiệm thu của bạn'),
      Expanded(
        child: d == null
            ? Loading(err: err, retry: load)
            : RefreshIndicator(onRefresh: load, child: _body(d)),
      ),
    ]);
  }

  Widget _body(Json d) {
    final m = d['m'] as Json;
    final approved = asInt(m['approved']), owed = asInt(m['owed']);
    final bank = (d['bank'] as Map?) ?? const {};
    final user = (d['user'] as Map?) ?? const {};
    final adj = (d['adj'] as List?)?.cast<Json>() ?? const <Json>[];
    final pays = (d['pays'] as List?)?.cast<Json>() ?? const <Json>[];
    final hasBank = str(bank['owner']).isNotEmpty;

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      MoneyHero(label: 'Đã nhận tất cả', amount: asInt(m['paid']), stats: [('Chờ thanh toán', owed), ('Đang chờ duyệt', asInt(m['reviewing']))]),
      Lift(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Box(children: [
              Row(children: [
                const Expanded(child: Text('Lần thanh toán tới', style: T.bold)),
                Text('$approved/${cfg.payMin} hồ sơ', style: T.muted),
              ]),
              Segs(n: approved, total: cfg.payMin),
              Text(
                approved >= cfg.payMin
                    ? 'Đã đủ. Kế toán sẽ chuyển ${money(owed)} vào tài khoản của bạn.'
                    : 'Cần thêm ${cfg.payMin - approved} hồ sơ được duyệt để nhận ${money(owed)} trở lên.',
                style: T.muted,
              ),
            ]),
            Box(onTap: () => tabIndex.value = 3, children: [
              Row(spacing: 12, children: [
                const Avatar(child: Ic('bank', color: C.navy3)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(hasBank ? str(bank['name']) : 'Tài khoản nhận tiền', style: const TextStyle(fontWeight: FontWeight.w600, color: C.text)),
                    Text(
                      hasBank
                          ? '${str(bank['no'])} · ${str(bank['owner'])}'
                          : (str(user['bank']).isNotEmpty ? str(user['bank']) : 'Chưa có, bấm để thêm'),
                      style: T.muted,
                    ),
                  ]),
                ),
                const Ic('right', color: C.muted, size: 18),
              ]),
            ]),
            if (adj.isNotEmpty) ...[
              const Sec('Thưởng / trừ chờ trả'),
              Box(padding: EdgeInsets.zero, gap: 0, children: [
                for (var k = 0; k < adj.length; k++) _AdjRow(adj[k], top: k > 0, withDate: true),
              ]),
            ],
            const Sec('Lịch sử nhận tiền'),
            if (pays.isNotEmpty)
              Box(padding: EdgeInsets.zero, gap: 0, children: [
                for (var k = 0; k < pays.length; k++)
                  Tap(
                    top: k > 0,
                    onTap: () => push(context, PaymentScreen(id: asInt(pays[k]['id']))),
                    child: Row(spacing: 12, children: [
                      const Avatar(color: C.okBg, child: Ic('check', color: C.ok)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Text('Nhận ${money(asInt(pays[k]['total']))}', style: const TextStyle(fontWeight: FontWeight.w700, color: C.text)),
                          Text(
                            '${vnDate(str(pays[k]['created_at']))} · ${asInt(pays[k]['n'])} hồ sơ${str(pays[k]['note']).isNotEmpty ? ' · ${str(pays[k]['note'])}' : ''}',
                            style: T.muted,
                          ),
                        ]),
                      ),
                      const Ic('right', color: C.muted, size: 18),
                    ]),
                  ),
              ])
            else
              Empty(
                icon: 'wallet',
                title: 'Chưa nhận lần nào',
                text: 'Khi có đủ ${cfg.payMin} hồ sơ được duyệt, kế toán sẽ chuyển khoản và lịch sử hiện ở đây.',
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// 1 dòng thưởng (+, xanh) hoặc trừ (-, đỏ).
class _AdjRow extends StatelessWidget {
  const _AdjRow(this.a, {this.top = false, this.withDate = false});
  final Json a;
  final bool top, withDate;
  @override
  Widget build(BuildContext context) {
    final amount = asInt(a['amount']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: top ? const BoxDecoration(border: Border(top: BorderSide(color: C.line))) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text('${amount > 0 ? '+' : ''}${money(amount)}', style: TextStyle(fontWeight: FontWeight.w700, color: amount > 0 ? C.ok : C.bad)),
        Text(withDate ? '${str(a['note'])} · ${vnDate(str(a['created_at']))}' : str(a['note']), style: T.muted),
      ]),
    );
  }
}
