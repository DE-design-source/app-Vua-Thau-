// Báo cáo cho khách hàng (24/11/2026): sau khi tải ảnh lên, CTV gửi cập nhật công trình cho chủ nhà qua Zalo.
// Zalo không cho điền sẵn lời nhắn: bấm Gửi qua Zalo thì app chép lời nhắn rồi mở chat Zalo theo SĐT chủ nhà, CTV dán vào.
// Tên, SĐT chủ nhà chỉ lưu trên máy này, theo từng hồ sơ (máy chủ chưa có chỗ lưu).
// Link báo cáo: máy chủ chưa có trang báo cáo công khai. Khi GET /houses/{id} trả `report_url`, app tự thêm link vào
// lời nhắn, hiện dòng link và nút Link (chép link).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../live/scan_text.dart' show prettyPhone;
import '../page.dart';
import '../toast.dart';
import '../ui.dart';
import '../zalo.dart';
import 'house.dart';

const _store = FlutterSecureStorage();

/// Chủ nhà đã lưu cho hồ sơ: (tên, SĐT); chưa có thì ('', '').
Future<(String, String)> loadOwner(int hid) async {
  try {
    final s = await _store.read(key: 'owner_$hid');
    final j = s == null ? null : jsonDecode(s);
    if (j is Map) return (str(j['name']), str(j['phone']));
  } catch (_) {/* kho khoá hỏng: coi như chưa lưu */}
  return ('', '');
}

Future<void> saveOwner(int hid, String name, String phone) async {
  try {
    await _store.write(key: 'owner_$hid', value: jsonEncode({'name': name, 'phone': phone}));
  } catch (_) {/* vẫn gửi được, lần sau nhập lại */}
}

String _ddmm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Lời nhắn soạn sẵn gửi chủ nhà (CTV sửa được trước khi gửi).
String reportMessage({required String name, required String address, required String stage, required DateTime day, String link = ''}) {
  final hi = name.trim().isEmpty ? 'Chào anh/chị' : 'Chào ${name.trim()}';
  final where = address.trim().isEmpty ? 'công trình nhà mình' : 'công trình ${address.trim()}';
  final st = stage.trim().isEmpty ? '' : ', giai đoạn ${stage.trim().toLowerCase()}';
  return [
    '$hi, em là cộng tác viên Vua Thầu. Hôm nay (${_ddmm(day)}) em đã chụp cập nhật $where$st ạ.',
    if (link.trim().isNotEmpty) 'Anh/chị xem ảnh thực tế tại: ${link.trim()}',
  ].join('\n');
}

class ReportScreen extends StatefulWidget {
  /// uploaded: mở ngay sau khi tải ảnh từ camera. openHouse: đóng thì sang Chi tiết hồ sơ (hồ sơ mới tạo).
  const ReportScreen({super.key, required this.id, this.uploaded = false, this.openHouse = false});
  final int id;
  final bool uploaded, openHouse;
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with PageData {
  @override
  String get path => '/houses/${widget.id}';

  final name = TextEditingController(), phone = TextEditingController(), msg = TextEditingController();
  bool editing = true, msgTouched = false, sent = false, sending = false;
  String phoneErr = '';

  Json get _house => ((d?['house'] as Map?) ?? const {}).cast<String, dynamic>();
  String get _link {
    final u = Uri.tryParse(str(d?['report_url']).trim());
    return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty ? u.toString() : '';
  }

  @override
  void initState() {
    super.initState();
    name.addListener(_fillMsg);
    loadOwner(widget.id).then((o) {
      if (!mounted) return;
      // CTV đã bắt đầu gõ trong lúc đọc kho: giữ những gì đang gõ
      if (name.text.isEmpty && phone.text.isEmpty) {
        name.text = o.$1;
        phone.text = o.$2;
      }
      setState(() => editing = zaloPhone(phone.text) == null);
      _fillMsg();
    });
  }

  @override
  void onData(Json j) => _fillMsg();

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    msg.dispose();
    super.dispose();
  }

  /// Soạn lại lời nhắn theo tên chủ nhà / thông tin công trình, khi CTV chưa tự sửa.
  void _fillMsg() {
    if (msgTouched || d == null) return;
    final h = _house;
    msg.text = reportMessage(name: name.text, address: str(h['address']), stage: str(h['stage']), day: DateTime.now(), link: _link);
  }

  void finish() {
    if (widget.openHouse) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HouseScreen(id: widget.id)));
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> send() async {
    final p = zaloPhone(phone.text);
    if (p == null) {
      setState(() {
        editing = true;
        phoneErr = phone.text.trim().isEmpty ? 'Nhập SĐT Zalo của chủ nhà.' : 'SĐT chưa đúng: số di động 10 số, bắt đầu bằng 0.';
      });
      return;
    }
    final text = msg.text.trim();
    if (text.isEmpty) {
      toast('Lời nhắn đang trống.');
      return;
    }
    setState(() {
      sending = true;
      phoneErr = '';
      editing = false;
    });
    phone.text = p;
    await saveOwner(widget.id, name.text.trim(), p);
    await Clipboard.setData(ClipboardData(text: text));
    final ok = await openZaloChat(p);
    if (!mounted) return;
    setState(() {
      sending = false;
      sent = sent || ok;
    });
    toast(ok
        ? 'Đã chép lời nhắn. Trong Zalo, chạm giữ ô nhập tin, chọn Dán rồi gửi.'
        : 'Không mở được Zalo. Lời nhắn đã chép, mở Zalo và gửi cho ${prettyPhone(p)}.');
  }

  Future<void> copyLink() async {
    await Clipboard.setData(ClipboardData(text: _link));
    toast('Đã chép link báo cáo.');
  }

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    final ps = (d?['photos'] as List?)?.cast<Json>() ?? const <Json>[];
    final link = _link;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) finish();
      },
      child: Scaffold(
        body: Column(children: [
          VtAppBar(
            title: 'Báo cáo cho khách hàng',
            sub: widget.uploaded ? 'Bước cuối · gửi cập nhật hôm nay' : '${hsId(widget.id)} · gửi cập nhật cho chủ nhà',
            back: true,
            close: true,
            onBack: finish,
          ),
          Expanded(
            child: d == null
                ? Loading(err: err, retry: load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      if (widget.uploaded) ...[
                        Note(tone: 'ok', icon: 'check', title: 'Đã tải ảnh lên hồ sơ ${hsId(widget.id)}', text: 'Gửi cập nhật cho chủ nhà qua Zalo, hoặc bấm Bỏ qua.'),
                        const SizedBox(height: 4),
                      ],
                      const Sec('XEM TRƯỚC BÁO CÁO'),
                      const SizedBox(height: 8),
                      _preview(ps, link),
                      const SizedBox(height: 8),
                      const Sec('GỬI CHO'),
                      const SizedBox(height: 8),
                      _owner(),
                      const SizedBox(height: 22),
                      Field(
                        label: 'LỜI NHẮN',
                        controller: msg,
                        multiline: true,
                        capitalization: TextCapitalization.sentences,
                        onChanged: (_) => msgTouched = true,
                        hint: 'Bấm Gửi qua Zalo: app chép lời nhắn này, bạn dán vào khung chat với chủ nhà.',
                      ),
                    ],
                  ),
          ),
          if (d != null)
            Container(
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
              padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
              child: Row(spacing: 8, children: [
                Expanded(child: Btn(sent ? 'Gửi lại qua Zalo' : 'Gửi qua Zalo', icon: 'chat', kind: BtnKind.primary, busy: sending, onPressed: send)),
                TextButton(
                  onPressed: finish,
                  child: Text(sent ? 'Xong' : 'Bỏ qua', style: const TextStyle(color: C.muted, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (link.isNotEmpty) Btn('Link', icon: 'link', onPressed: copyLink),
              ]),
            ),
        ]),
      ),
    );
  }

  /// Thẻ xem trước: ảnh bìa + tên công trình, giai đoạn, số ảnh, 4 ảnh nhỏ, link báo cáo (khi máy chủ có).
  Widget _preview(List<Json> ps, String link) {
    final h = _house;
    final addr = str(h['address']).split(',').first.trim();
    final stage = str(h['stage']);
    final gps = ps.isNotEmpty && ps.every((p) => p['lat'] != null);
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line2), borderRadius: BorderRadius.circular(R.card)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(fit: StackFit.expand, children: [
            if (ps.isEmpty)
              Container(color: C.soft, alignment: Alignment.center, child: const Ic('image', color: C.subtle, size: 32))
            else
              NetPhoto.id(asInt(ps.first['id'])),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)], stops: [0.45, 1]),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                const Text('VUA THẦU MAP · BÁO CÁO CÔNG TRÌNH', style: TextStyle(color: C.amber, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                Text('${addr.isNotEmpty ? addr : 'Công trình'} · ${_ddmm(DateTime.now())}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.25)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (stage.isNotEmpty) Pill(stage, tone: 'done'),
              Pill('${ps.length} ảnh', tone: 'draft'),
              if (gps) const Pill('Có GPS & giờ chụp', tone: 'ok', icon: 'check'),
            ]),
            if (ps.length > 1)
              Row(spacing: 6, children: [
                for (var k = 0; k < 4; k++)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: k >= ps.length
                          ? const SizedBox.shrink()
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(R.ctl),
                              child: Stack(fit: StackFit.expand, children: [
                                NetPhoto.id(asInt(ps[k]['id'])),
                                if (k == 3 && ps.length > 4)
                                  Container(
                                    color: const Color(0x80000000),
                                    alignment: Alignment.center,
                                    child: Text('+${ps.length - 4}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                  ),
                              ]),
                            ),
                    ),
                  ),
              ]),
            if (link.isNotEmpty)
              Row(spacing: 6, children: [
                const Ic('link', color: C.muted, size: 14),
                Expanded(child: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.muted)),
                TextButton(onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication), child: const Text('Xem')),
              ]),
          ]),
        ),
      ]),
    );
  }

  /// Chủ nhà: đã có SĐT hợp lệ thì hiện thẻ (bấm Đổi để sửa), chưa có thì hiện 2 ô nhập.
  Widget _owner() {
    final p = zaloPhone(phone.text);
    if (!editing && p != null) {
      final n = name.text.trim();
      return Box(padding: const EdgeInsets.fromLTRB(12, 10, 4, 10), children: [
        Row(spacing: 12, children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: C.blueBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(initials(n.isEmpty ? 'Chủ nhà' : n), style: const TextStyle(color: C.navy3, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(n.isEmpty ? 'Chủ nhà' : '$n · Chủ nhà', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bold),
              Text(prettyPhone(p), style: T.muted),
            ]),
          ),
          TextButton(onPressed: () => setState(() => editing = true), child: const Text('Đổi')),
        ]),
      ]);
    }
    return Box(gap: 14, children: [
      Field(label: 'TÊN CHỦ NHÀ', controller: name, placeholder: 'VD: Chị Tuyết', capitalization: TextCapitalization.words),
      Field(
        label: 'SĐT ZALO CỦA CHỦ NHÀ',
        controller: phone,
        placeholder: '0912 345 678',
        keyboardType: TextInputType.phone,
        error: phoneErr.isEmpty ? null : phoneErr,
        onChanged: (_) {
          if (phoneErr.isNotEmpty) setState(() => phoneErr = '');
        },
        hint: 'Chỉ lưu trên máy này, để mở chat Zalo với chủ nhà.',
      ),
    ]);
  }
}
