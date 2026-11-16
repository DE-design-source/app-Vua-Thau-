// Thu nhập (GET /ctv/income): tổng tiền, lần thanh toán tới, tài khoản nhận tiền, lịch sử nhận tiền.
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
  String get path => '/ctv/income';
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
    final m = (d['money'] as Map?) ?? const {};
    final approved = asInt(m['approved']), owed = asInt(m['owed']);
    final bank = (d['bank'] as Map?) ?? const {};
    final userBank = str(d['user_bank']);
    final adj = (d['adjustments'] as List?)?.cast<Json>() ?? const <Json>[];
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
                Text('$approved/${cfg.payMin} hồ sơ', style: T.num.copyWith(color: C.muted, fontSize: 13.5)),
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
                const Avatar(size: 40, child: Ic('bank', color: C.navy3, size: 18)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(hasBank ? str(bank['name']) : 'Tài khoản nhận tiền', style: const TextStyle(fontWeight: FontWeight.w600, color: C.text)),
                    if (hasBank)
                      Text('${str(bank['no'])} · ${str(bank['owner'])}', style: T.mono)
                    else
                      Text(userBank.isNotEmpty ? userBank : 'Chưa có, bấm để thêm', style: T.muted),
                  ]),
                ),
                const Ic('right', color: C.subtle, size: 16),
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
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                          Row(spacing: 8, children: [
                            Text(pcId(pays[k]['id']), style: T.mono),
                            Text(vnDate(str(pays[k]['created_at'])), style: T.hint.copyWith(color: C.subtle, fontFeatures: const [FontFeature.tabularFigures()])),
                          ]),
                          Text(
                            '${asInt(pays[k]['house_count'])} hồ sơ${str(pays[k]['ref']).isNotEmpty ? ' · mã GD ${str(pays[k]['ref'])}' : ''}',
                            style: T.muted,
                          ),
                        ]),
                      ),
                      Text('+${money(asInt(pays[k]['total']))}', style: T.num.copyWith(color: C.ok)),
                      const Ic('right', color: C.subtle, size: 16),
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
        Text('${amount > 0 ? '+' : ''}${money(amount)}', style: T.num.copyWith(color: amount > 0 ? C.ok : C.bad)),
        Text(withDate ? '${str(a['note'])} · ${vnDate(str(a['created_at']))}' : str(a['note']), style: T.muted),
      ]),
    );
  }
}
