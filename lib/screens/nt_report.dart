// "Báo cáo cho khách hàng" (thiết kế 24/11/2026): bước cuối sau khi tải nhật ký lên, hoặc bấm Chia sẻ ở 1 nhật ký.
// Mỗi nhật ký có link công khai /bc/<mã> (chủ nhà mở xem ảnh thực tế, không cần đăng nhập).
// Nhà thầu sửa lời nhắn rồi bấm "Link gởi khách hàng": mở bảng chia sẻ của máy (Zalo, Messenger, SMS...);
// máy / trình duyệt không chia sẻ được thì chép lời nhắn + link vào bộ nhớ tạm để dán.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../page.dart';
import '../stamp.dart' show p2;
import '../toast.dart';
import '../ui.dart';

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
  final msg = TextEditingController();
  bool msgSet = false, sharing = false;

  String get url => '$host${str(d?['path'])}';

  @override
  void onData(Json j) {
    api('/public/bc/${str(j['code'])}').then((r) {
      if (!mounted) return;
      setState(() => rep = r);
      if (!msgSet) {
        msgSet = true;
        msg.text = _greeting(r);
      }
    }).catchError((Object e) {
      if (mounted) setState(() => err = errMsg(e));
    });
  }

  @override
  void dispose() {
    msg.dispose();
    super.dispose();
  }

  /// "Chào anh/chị, hôm nay đội đã lắp cốp pha cột tầng 2. Anh/chị xem ảnh thực tế tại link bên dưới ạ."
  String _greeting(Json r) {
    var note = str(r['note']).trim();
    if (note.endsWith('.')) note = note.substring(0, note.length - 1);
    final what = note.isEmpty ? 'cập nhật tiến độ ${str(r['project'])}' : note[0].toLowerCase() + note.substring(1);
    return 'Chào anh/chị, hôm nay đội đã $what. Anh/chị xem ảnh thực tế tại link bên dưới ạ.';
  }

  Future<void> share() async {
    final text = '${msg.text.trim()}\n$url';
    setState(() => sharing = true);
    try {
      final r = await SharePlus.instance.share(ShareParams(text: text, subject: 'Báo cáo thi công ${str(rep?['project'])}'));
      if (r.status == ShareResultStatus.unavailable) throw Exception('unavailable');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      toast('Đã chép lời nhắn và link. Mở Zalo / Messenger, dán vào tin nhắn gửi khách.');
    } finally {
      if (mounted) setState(() => sharing = false);
    }
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
                      child: Text('LỜI NHẮN', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: Color(0xFF94A3B8))),
                    ),
                    TextField(
                      controller: msg,
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
                  label: const Text('Link gởi khách hàng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bỏ qua', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
            ),
          ]),
        ),
      ]),
    );
  }
}
