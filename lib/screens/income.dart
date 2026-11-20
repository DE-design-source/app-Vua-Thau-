// Thu nhập (GET /ctv/income), theo hệ thiết kế 18/11/2026 (thẻ tiền như trang duyệt hồ sơ):
// thẻ nổi: tiền đã nhận (gạch chân) + khung 2 ô (chờ thanh toán | đang chờ duyệt), lần thanh toán tới (thanh n ô),
// khung chuyển khoản 3 ô (bấm để sửa); thưởng / trừ; lịch sử nhận tiền.
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
  Widget build(BuildContext context) {
    final d = this.d;
    return Column(children: [
      const VtAppBar(title: 'Thu nhập', sub: 'Tiền nghiệm thu của bạn', back: true),
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
    final full = approved >= cfg.payMin;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 32), children: [
      // ---- thẻ tiền ----
      Box(raised: true, padding: const EdgeInsets.all(20), gap: 16, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
          Text(money(asInt(m['paid'])),
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w600, color: C.text, decoration: TextDecoration.underline, letterSpacing: -0.5, height: 1.2)),
          const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('đã nhận', style: TextStyle(fontSize: 16, color: C.text))),
        ]),
        FieldBox(radius: 8, rows: [
          [FieldCell('Chờ thanh toán', money(owed)), FieldCell('Đang chờ duyệt', money(asInt(m['reviewing'])))],
        ]),
        const Divider(height: 1, color: C.line),
        Row(children: [
          Expanded(child: Text('Lần thanh toán tới', style: T.cap)),
          Text('$approved/${cfg.payMin} hồ sơ', style: T.num.copyWith(fontSize: 13, color: full ? C.ok : C.muted)),
        ]),
        Segs(n: approved, total: cfg.payMin),
        Text(
          full
              ? 'Đã đủ. Kế toán sẽ chuyển ${money(owed)} vào tài khoản của bạn.'
              : 'Cần thêm ${cfg.payMin - approved} hồ sơ được duyệt để nhận ${money(owed)} trở lên.',
          style: T.muted,
        ),
        const Divider(height: 1, color: C.line),
        Row(children: [
          Expanded(child: Text('Chuyển khoản về', style: T.cap)),
          InkWell(
            onTap: () => openAccount(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(hasBank ? 'Sửa' : 'Thêm tài khoản',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text, decoration: TextDecoration.underline)),
            ),
          ),
        ]),
        if (hasBank)
          FieldBox(radius: 8, rows: [
            [FieldCell('Ngân hàng', str(bank['name'])), FieldCell('Số tài khoản', str(bank['no']))],
            [FieldCell('Chủ tài khoản', str(bank['owner']))],
          ])
        else
          Note(
            tone: 'wait',
            icon: 'bank',
            title: 'Chưa có tài khoản nhận tiền',
            onTap: () => openAccount(context),
            text: userBank.isNotEmpty ? 'Đang lưu: “$userBank”. Nhập lại theo 3 ô để kế toán chuyển nhanh, đúng.' : 'Thêm để kế toán chuyển tiền cho bạn.',
          ),
      ]),

      // ---- thưởng / trừ ----
      if (adj.isNotEmpty) ...[
        const _H3('Thưởng / trừ chờ trả'),
        Box(padding: EdgeInsets.zero, gap: 0, children: [
          for (var k = 0; k < adj.length; k++) _AdjRow(adj[k], top: k > 0),
        ]),
      ],

      // ---- lịch sử ----
      _H3('Lịch sử nhận tiền', right: pays.isNotEmpty ? '${pays.length} lần' : null),
      if (pays.isNotEmpty)
        Box(padding: EdgeInsets.zero, gap: 0, children: [
          for (var k = 0; k < pays.length; k++) _PayRow(pays[k], top: k > 0),
        ])
      else
        Empty(
          icon: 'wallet',
          title: 'Chưa nhận lần nào',
          text: 'Khi có đủ ${cfg.payMin} hồ sơ được duyệt, kế toán sẽ chuyển khoản và lịch sử hiện ở đây.',
        ),
    ]);
  }
}

/// Tiêu đề mục 18px đậm (như "Xem ảnh nhật ký công trình" bên web).
class _H3 extends StatelessWidget {
  const _H3(this.text, {this.right});
  final String text;
  final String? right;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 28, 2, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(text, style: T.secT)),
          if (right != null) Text(right!, style: T.hint),
        ]),
      );
}

/// 1 lần nhận tiền: dấu tích xanh, mã phiếu + ngày, số hồ sơ; số tiền bên phải.
class _PayRow extends StatelessWidget {
  const _PayRow(this.p, {this.top = false});
  final Json p;
  final bool top;
  @override
  Widget build(BuildContext context) => Tap(
        top: top,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        onTap: () => push(context, PaymentScreen(id: asInt(p['id']))),
        child: Row(spacing: 12, children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: C.okBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.check_rounded, color: C.ok, size: 20),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(vnDate(str(p['created_at'])), style: T.bold),
              Text(
                '${pcId(p['id'])} · ${asInt(p['house_count'])} hồ sơ${str(p['ref']).isNotEmpty ? ' · GD ${str(p['ref'])}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.muted,
              ),
            ]),
          ),
          Text('+${money(asInt(p['total']))}', style: T.num.copyWith(color: C.ok)),
          const Ic('right', color: C.subtle, size: 16),
        ]),
      );
}

/// 1 dòng thưởng (+, xanh) hoặc trừ (-, đỏ).
class _AdjRow extends StatelessWidget {
  const _AdjRow(this.a, {this.top = false});
  final Json a;
  final bool top;
  @override
  Widget build(BuildContext context) {
    final amount = asInt(a['amount']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: top ? const BoxDecoration(border: Border(top: BorderSide(color: C.line))) : null,
      child: Row(spacing: 12, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(str(a['note']).isNotEmpty ? str(a['note']) : (amount > 0 ? 'Thưởng' : 'Trừ'), style: T.bold),
            Text(vnDate(str(a['created_at'])), style: T.muted),
          ]),
        ),
        Text('${amount > 0 ? '+' : ''}${money(amount)}', style: T.num.copyWith(color: amount > 0 ? C.ok : C.bad)),
      ]),
    );
  }
}
