// "Báo cáo cho khách hàng" (thiết kế 24/11/2026): bước cuối sau khi tải nhật ký lên, hoặc bấm Chia sẻ ở 1 nhật ký.
// Mỗi nhật ký có link công khai /bc/<mã> (chủ nhà mở xem ảnh thực tế, không cần đăng nhập).
// Nhà thầu sửa lời nhắn rồi bấm "Gởi khách hàng": mở bảng chia sẻ của máy (Zalo, Messenger, SMS...);
// máy / trình duyệt không chia sẻ được thì chép lời nhắn + link vào bộ nhớ tạm để dán.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../live/scan_text.dart' show prettyPhone;
import '../page.dart';
import '../stamp.dart' show p2;
import '../toast.dart';
import '../ui.dart';
import '../zalo.dart';

const _store = FlutterSecureStorage();

/// Chủ nhà của dự án (tên, SĐT Zalo) lưu trên máy, theo từng dự án; chưa có: ('', '').
Future<(String, String)> loadNtOwner(int pid) async {
  try {
    final s = await _store.read(key: 'nt_owner_$pid');
    final j = s == null ? null : jsonDecode(s);
    if (j is Map) return (str(j['name']), str(j['phone']));
  } catch (_) {/* kho khoá hỏng: coi như chưa lưu */}
  return ('', '');
}

Future<void> saveNtOwner(int pid, String name, String phone) async {
  try {
    await _store.write(key: 'nt_owner_$pid', value: jsonEncode({'name': name, 'phone': phone}));
  } catch (_) {/* vẫn gửi được, lần sau nhập lại */}
}

const _ink = Color(0xFF0B2340), _blue = Color(0xFF0A4BB5), _gold = Color(0xFFFFB81C), _zalo = Color(0xFF0068FF);

/// Hạng mục chọn nhanh ở màn Xác nhận nhật ký (camera): nhận ra ở đầu mô tả để làm thẻ.
const ntCategories = ['Cốp pha', 'Cốt thép', 'Đổ bê tông', 'Xây tô'];

class NtReportScreen extends StatefulWidget {
  /// uploaded: số ảnh vừa tải (hiện dải "Đã tải lên N ảnh."); 0: mở từ nhật ký cũ.
  const NtReportScreen({super.key, required this.projectId, required this.logId, this.uploaded = 0});
  final int projectId, logId, uploaded;
  @override
  State<NtReportScreen> createState() => _NtReportScreenState();
}

class _NtReportScreenState extends State<NtReportScreen> with PageData {
  @override
  String get path => '/nt/projects/${widget.projectId}/logs/${widget.logId}/report';
  Json? rep; // nội dung báo cáo công khai (đúng như chủ nhà sẽ thấy)
  final msg = TextEditingController(), owner = TextEditingController(), phone = TextEditingController();
  bool msgTouched = false, sharing = false, editingOwner = true, sent = false;
  String phoneErr = '';

  String get url => '$host${str(d?['path'])}';

  @override
  void initState() {
    super.initState();
    owner.addListener(_fillMsg);
    // chủ nhà đã gửi lần trước cho dự án này: điền sẵn (gửi Zalo mỗi ngày không phải nhập lại)
    loadNtOwner(widget.projectId).then((o) {
      if (!mounted) return;
      if (owner.text.isEmpty && phone.text.isEmpty) {
        owner.text = o.$1;
        phone.text = o.$2;
      }
      setState(() => editingOwner = zaloPhone(phone.text) == null);
      _fillMsg();
    });
  }

  @override
  void onData(Json j) {
    api('/public/bc/${str(j['code'])}').then((r) {
      if (!mounted) return;
      setState(() => rep = r);
      _fillMsg();
    }).catchError((Object e) {
      if (mounted) setState(() => err = errMsg(e));
    });
  }

  /// Soạn lại lời nhắn theo tên chủ nhà, khi nhà thầu chưa tự sửa.
  void _fillMsg() {
    final r = rep;
    if (msgTouched || r == null) return;
    msg.text = _greeting(r);
  }

  @override
  void dispose() {
    msg.dispose();
    owner.dispose();
    phone.dispose();
    super.dispose();
  }

  /// "Chào anh/chị, hôm nay đội đã lắp cốp pha cột tầng 2. Anh/chị xem ảnh thực tế tại link bên dưới ạ."
  /// Mô tả nhật ký = "Cốp pha, Cốt thép. Lắp cốp pha cột tầng 2" (hạng mục chọn nhanh + ghi chú):
  /// "hôm nay đội đã lắp cốp pha cột tầng 2 (hạng mục: cốp pha, cốt thép)"; chỉ có hạng mục: "thi công cốp pha, cốt thép".
  String _greeting(Json r) {
    var note = str(r['note']).trim();
    var cats = '';
    final dot = note.indexOf('. ');
    final head = dot > 0 ? note.substring(0, dot) : note.replaceAll(RegExp(r'\.$'), '');
    if (head.split(', ').every(ntCategories.contains)) {
      cats = head.toLowerCase();
      note = dot > 0 ? note.substring(dot + 2).trim() : '';
    }
    if (note.endsWith('.')) note = note.substring(0, note.length - 1);
    String low(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
    // quy tắc lời nhắn (góp ý 24/11): "Chào anh chị, hôm nay đội thi công đã <hạng mục>, <ghi chú>,
    // anh chị xem qua ảnh báo cáo công trình ạ, em cám ơn anh chị ạ"
    final what = [if (cats.isNotEmpty) cats, if (note.isNotEmpty) low(note)].join(', ');
    final hi = owner.text.trim().isEmpty ? 'Chào anh chị' : 'Chào ${owner.text.trim()}';
    return '$hi, hôm nay đội thi công đã ${what.isNotEmpty ? what : 'cập nhật tiến độ công trình ${str(r['project'])}'}, '
        'anh chị xem qua ảnh báo cáo công trình ạ, em cám ơn anh chị ạ.';
  }

  /// "Gởi khách hàng": có SĐT Zalo chủ nhà thì chép lời nhắn + link rồi mở chat Zalo (Zalo không cho điền sẵn
  /// tin, nhà thầu dán vào); chưa có SĐT thì mở bảng chia sẻ của máy (Zalo, Messenger, SMS...).
  Future<void> share() async {
    final text = '${msg.text.trim()}\n$url';
    final raw = phone.text.trim();
    final p = zaloPhone(raw);
    if (raw.isNotEmpty && p == null) {
      setState(() {
        editingOwner = true;
        phoneErr = 'SĐT chưa đúng: số di động 10 số, bắt đầu bằng 0. Để trống để chọn app khác.';
      });
      return;
    }
    setState(() {
      sharing = true;
      phoneErr = '';
    });
    try {
      if (p != null) {
        phone.text = p;
        editingOwner = false;
        await saveNtOwner(widget.projectId, owner.text.trim(), p);
        await Clipboard.setData(ClipboardData(text: text));
        final ok = await openZaloChat(p);
        sent = sent || ok;
        toast(ok
            ? 'Đã chép lời nhắn và link. Trong Zalo, chạm giữ ô nhập tin, chọn Dán rồi gửi.'
            : 'Không mở được Zalo. Lời nhắn và link đã chép, mở Zalo và gửi cho ${prettyPhone(p)}.');
        return;
      }
      final r = await SharePlus.instance.share(ShareParams(text: text, subject: 'Báo cáo thi công ${str(rep?['project'])}'));
      if (r.status == ShareResultStatus.unavailable) throw Exception('unavailable');
      sent = sent || r.status == ShareResultStatus.success;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      toast('Đã chép lời nhắn và link. Mở Zalo / Messenger, dán vào tin nhắn gửi khách.');
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  /// Gửi cho: chủ nhà đã có SĐT Zalo thì hiện thẻ (bấm Đổi), chưa có thì 2 ô nhập.
  Widget _owner() {
    final p = zaloPhone(phone.text);
    if (!editingOwner && p != null) {
      final n = owner.text.trim();
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE3E8F0))),
        child: Row(spacing: 12, children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Color(0xFFE8F1FF), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(initials(n.isEmpty ? 'Chủ nhà' : n), style: const TextStyle(color: _zalo, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(n.isEmpty ? 'Chủ nhà' : '$n · Chủ nhà', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bold),
              Text('Zalo ${prettyPhone(p)}', style: T.muted),
            ]),
          ),
          TextButton(onPressed: () => setState(() => editingOwner = true), child: const Text('Đổi')),
        ]),
      );
    }
    InputDecoration deco(String label, String hint, {String? error}) => InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          errorMaxLines: 2,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _blue, width: 1.5)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      TextField(controller: owner, textCapitalization: TextCapitalization.words, decoration: deco('Tên chủ nhà', 'VD: Anh Hưng')),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        onChanged: (_) {
          if (phoneErr.isNotEmpty) setState(() => phoneErr = '');
        },
        decoration: deco('SĐT Zalo của chủ nhà', '0912 345 678', error: phoneErr.isEmpty ? null : phoneErr),
      ),
      const Text('Có SĐT: bấm nút dưới là mở chat Zalo với chủ nhà. Chỉ lưu trên máy này.', style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
    ]);
  }

  Widget _chip(String s, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(s, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _preview(Json r) {
    final photos = ((r['photos'] as List?) ?? const []).map((e) => '$host$e').toList();
    final t = DateTime.tryParse(str(r['taken_at']))?.toLocal();
    final note = str(r['note']);
    final cats = [for (final c in ntCategories) if (note.startsWith(c) || note.contains('$c,') || note.contains('$c.')) c];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(fit: StackFit.expand, children: [
            photos.isNotEmpty ? Image.network('${photos.first}?size=small', fit: BoxFit.cover) : Container(color: _ink),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [.3, 1], colors: [Color(0x000B2340), Color(0xD90B2340)]),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(
                  '${str(r['company']).isNotEmpty ? str(r['company']).toUpperCase() : 'NHÀ THẦU'} · NHẬT KÝ THI CÔNG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _gold, letterSpacing: .3),
                ),
                Text(
                  '${str(r['project'])}${t != null ? ' · ${p2(t.day)}/${p2(t.month)}' : ''}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in cats) _chip(c, const Color(0xFFEAF1FC), _blue),
              _chip('${photos.length} ảnh${asInt(r['videos']) > 0 ? ' · ${r['videos']} video' : ''}', const Color(0xFFF1F5F9), const Color(0xFF475569)),
              if (r['gps'] == true) _chip('✓ Xác minh GPS & giờ chụp', const Color(0xFFE8F6EE), const Color(0xFF166534)),
            ]),
            if (photos.length > 1)
              Row(spacing: 4, children: [
                for (var k = 1; k < photos.length && k <= 4; k++)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(fit: StackFit.expand, children: [
                          Image.network('${photos[k]}?size=small', fit: BoxFit.cover),
                          if (k == 4 && photos.length > 5)
                            Container(
                              color: const Color(0x990B2340),
                              alignment: Alignment.center,
                              child: Text('+${photos.length - 5}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            ),
                        ]),
                      ),
                    ),
                  ),
                for (var k = photos.length; k <= 4; k++) const Expanded(child: SizedBox()),
              ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(8)),
              child: Row(spacing: 6, children: [
                const Icon(Icons.link, size: 14, color: Color(0xFF64748B)),
                Expanded(
                  child: Text(url.replaceFirst(RegExp(r'^https?://'), ''),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                ),
                InkWell(
                  onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text('Xem', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _blue)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rep;
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Column(children: [
        // đầu trang navy chuyển màu
        Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B2340), Color(0xFF102C5E), Color(0xFF1B3F94)], stops: [0, .55, 1])),
          padding: EdgeInsets.fromLTRB(4, safe.top + 8, 16, 12),
          child: Row(spacing: 4, children: [
            IconButton(tooltip: 'Đóng', onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.close, color: Colors.white)),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Báo cáo cho khách hàng', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('Bước cuối · gửi cập nhật hôm nay', style: TextStyle(fontSize: 11.5, color: Color(0xFF9FB3CF))),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: r == null
              ? Loading(err: err, retry: load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (widget.uploaded > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFFE8F6EE), borderRadius: BorderRadius.circular(12)),
                        child: Row(spacing: 10, children: [
                          const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                          Expanded(
                            child: Text('Đã tải lên ${widget.uploaded} ảnh. Gửi link cho chủ nhà xem tiến độ hôm nay.',
                                style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF14532D), fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 6),
                      child: Text('XEM TRƯỚC BÁO CÁO', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: Color(0xFF94A3B8))),
                    ),
                    _preview(r),
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 6),
                      child: Text('GỬI CHO', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: Color(0xFF94A3B8))),
                    ),
                    _owner(),
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 6),
                      child: Text('LỜI NHẮN', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: Color(0xFF94A3B8))),
                    ),
                    TextField(
                      controller: msg,
                      onChanged: (_) => msgTouched = true,
                      minLines: 3,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 13.5, height: 1.4),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Lời nhắn gửi chủ nhà',
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _blue, width: 1.5)),
                      ),
                    ),
                  ],
                ),
        ),
        Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE3E8F0)))),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safe.bottom),
          child: Row(spacing: 8, children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _zalo, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: r == null || sharing ? null : share,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Gởi khách hàng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(sent ? 'Xong' : 'Bỏ qua', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
            ),
          ]),
        ),
      ]),
    );
  }
}
