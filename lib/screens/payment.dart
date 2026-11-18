// 1 lần nhận tiền (GET /batches/{id}): số tiền, mã giao dịch, ảnh biên lai kế toán gửi, hồ sơ được trả, thưởng / trừ.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../page.dart';
import '../ui.dart';
import 'house.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.id});
  final int id;
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with PageData {
  @override
  String get path => '/batches/${widget.id}';

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    if (d == null) {
      return Scaffold(body: Column(children: [VtAppBar(title: pcId(widget.id), back: true), Expanded(child: Loading(err: err, retry: load))]));
    }
    final b = (d['batch'] as Map).cast<String, dynamic>();
    final rows = (d['rows'] as List?)?.cast<Json>() ?? const <Json>[];
    final adjs = (d['adjustments'] as List?)?.cast<Json>() ?? const <Json>[];
    final receipt = b['has_receipt'] == true
        ? '$base/batches/${b['id']}/receipt?v=${Uri.encodeQueryComponent(str(b['receipt_version']))}'
        : null;

    return Scaffold(
      body: Column(children: [
        VtAppBar(title: pcId(b['id']), sub: vnTime(str(b['created_at'])), back: true),
        Expanded(
          child: ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.paddingOf(context).bottom), children: [
            // thẻ tiền (như màn Thu nhập): đã chuyển khoản, số tiền gạch chân, khung ô thông tin chuyển khoản
            Box(raised: true, padding: const EdgeInsets.all(20), gap: 14, children: [
              const Row(children: [Pill('Đã chuyển khoản', tone: 'ok', icon: 'check')]),
              Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
                Text(money(asInt(d['total'])),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w600, color: C.text, decoration: TextDecoration.underline, letterSpacing: -0.5, height: 1.2)),
                const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('bạn đã nhận', style: TextStyle(fontSize: 16, color: C.text))),
              ]),
              Text('${rows.length} hồ sơ${adjs.isNotEmpty ? ' · ${adjs.length} khoản thưởng/trừ' : ''}', style: T.muted),
              FieldBox(radius: 8, rows: [
                [FieldCell('Tài khoản nhận', str(b['ctv_bank']))],
                [
                  FieldCell('Mã giao dịch', str(b['ref']).isNotEmpty ? str(b['ref']) : 'Không ghi'),
                  FieldCell('Kế toán chuyển', str(b['by_name'])),
                ],
              ]),
            ]),
            const _H3('Ảnh biên lai'),
            if (receipt != null)
              Semantics(
                button: true,
                label: 'Ảnh biên lai chuyển khoản, bấm để phóng to',
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _Receipt(url: receipt, id: asInt(b['id'])))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(R.card),
                    child: Stack(children: [
                      NetPhoto(receipt, height: 240, width: double.infinity, alignment: Alignment.topCenter),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), boxShadow: cardShadow),
                          child: const Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                            Ic('eye', color: C.text, size: 16),
                            Text('Bấm để xem rõ', style: TextStyle(color: C.text, fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              )
            else
              const Text('Kế toán chưa gửi ảnh biên lai. Mã giao dịch ở trên dùng để đối chiếu với ngân hàng.', style: T.muted),
            if (adjs.isNotEmpty) ...[
              const _H3('Thưởng / trừ'),
              Box(padding: EdgeInsets.zero, gap: 0, children: [
                for (var k = 0; k < adjs.length; k++)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: k > 0 ? const BoxDecoration(border: Border(top: BorderSide(color: C.line))) : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text('${asInt(adjs[k]['amount']) > 0 ? '+' : ''}${money(asInt(adjs[k]['amount']))}',
                          style: T.num.copyWith(color: asInt(adjs[k]['amount']) > 0 ? C.ok : C.bad)),
                      Text(str(adjs[k]['note']), style: T.muted),
                    ]),
                  ),
              ]),
            ],
            _H3('Hồ sơ được trả lần này', right: '${rows.length} hồ sơ'),
            Box(padding: EdgeInsets.zero, gap: 0, children: [
              for (var k = 0; k < rows.length; k++) _row(rows[k], k > 0),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _row(Json r, bool top) {
    final id = asInt(r['id']);
    final cover = r['cover_id'];
    return Tap(
      top: top,
      padding: const EdgeInsets.all(12),
      onTap: () => push(context, HouseScreen(id: id)),
      child: Row(spacing: 12, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.ctl),
          child: SizedBox(
            width: 48,
            height: 48,
            child: cover != null
                ? NetPhoto.id(asInt(cover), width: 48, height: 48)
                : Container(color: C.soft, alignment: Alignment.center, child: const Ic('image', color: C.subtle, size: 18)),
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text('${hsId(id)}${r['photos_total'] != null ? '  ${asInt(r['photos_valid'])}/${asInt(r['photos_total'])} ảnh đạt' : ''}', style: T.mono),
            Text(str(r['address']).isNotEmpty ? str(r['address']) : 'Chưa có địa chỉ',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: C.text)),
          ]),
        ),
        Text(money(asInt(r['amount'])), style: T.num.copyWith(fontSize: 14)),
        const Ic('right', color: C.subtle, size: 16),
      ]),
    );
  }
}

/// Tiêu đề mục 18px đậm.
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

class _Receipt extends StatelessWidget {
  const _Receipt({required this.url, required this.id});
  final String url;
  final int id;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(children: [
                  Expanded(child: Text('Biên lai ${pcId(id)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  IconButton(tooltip: 'Đóng', onPressed: () => Navigator.pop(context), icon: const Ic('x', color: Colors.white, size: 26)),
                ]),
              ),
              Expanded(child: InteractiveViewer(maxScale: 5, child: Center(child: NetPhoto(url, fit: BoxFit.contain)))),
            ]),
          ),
        ),
      );
}
