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
            Box(padding: const EdgeInsets.all(16), gap: 4, children: [
              const Row(spacing: 8, children: [
                Pill('Đã chuyển khoản', tone: 'ok', icon: 'check'),
              ]),
              const SizedBox(height: 8),
              const Text('BẠN ĐÃ NHẬN', style: T.formHead),
              Text(money(asInt(d['total'])), style: T.num.copyWith(fontSize: 30, letterSpacing: -0.8)),
              Text('${rows.length} hồ sơ${adjs.isNotEmpty ? ' · ${adjs.length} khoản thưởng/trừ' : ''}', style: T.muted),
            ]),
            const SizedBox(height: 12),
            Box(gap: 14, children: [
              _Fact('Tài khoản nhận', str(b['ctv_bank'])),
              _Fact('Mã giao dịch', str(b['ref']).isNotEmpty ? str(b['ref']) : 'Kế toán không ghi', mono: str(b['ref']).isNotEmpty),
              _Fact('Kế toán chuyển', str(b['by_name'])),
            ]),
            const SizedBox(height: 12),
            const Sec('Ảnh biên lai'),
            const SizedBox(height: 12),
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
                          decoration: BoxDecoration(color: C.text.withValues(alpha: .78), borderRadius: BorderRadius.circular(R.ctl)),
                          child: const Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                            Ic('eye', color: Colors.white, size: 16),
                            Text('Bấm để xem rõ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
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
              const SizedBox(height: 12),
              const Sec('Thưởng / trừ'),
              const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            const Sec('Hồ sơ được trả lần này'),
            const SizedBox(height: 12),
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

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.mono = false});
  final String label, value;
  final bool mono;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
        Text(label.toUpperCase(), style: T.formHead),
        Text(value.isNotEmpty ? value : '—', style: mono ? T.mono.copyWith(color: C.text, fontSize: 14) : T.body),
      ]);
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
