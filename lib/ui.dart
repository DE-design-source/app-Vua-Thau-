// Giao diện dùng chung, cùng hệ thiết kế với web quản lý (18/11/2026): font Be Vietnam Pro, nền trắng, chữ #222,
// thanh tiêu đề xanh navy chuyển màu, điểm nhấn vàng #f5b70a, nút chính xanh dương, thẻ bo 12 viền mảnh,
// nhãn ô nhỏ in hoa, khung thông tin đóng viền kiểu Airbnb.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';

abstract final class C {
  // Thương hiệu: navy (thanh tiêu đề, khung thương hiệu), vàng (điểm nhấn), xanh dương (nút chính, giai đoạn)
  static const navy = Color(0xFF002463), navy2 = Color(0xFF003A8C), navy3 = Color(0xFF0B3D91), navyDeep = Color(0xFF001A4D);
  static const amber = Color(0xFFF5B70A), amberBg = Color(0xFFFFF7E0), amberInk = Color(0xFF0F1E36);
  static const blue = Color(0xFF1D6FF2), blue2 = Color(0xFF1554C9), blueBg = Color(0xFFEAF1FE);
  // Nền, chữ, viền
  static const bg = Colors.white, card = Colors.white, text = Color(0xFF222222), muted = Color(0xFF6A6A6A);
  static const subtle = Color(0xFF8A8A8A), line = Color(0xFFEBEBEB), line2 = Color(0xFFDDDDDD), field = Color(0xFFB0B0B0);
  static const soft = Color(0xFFF7F7F7), placeholder = subtle, dot = Color(0xFFC4C4C4);
  // Chữ phụ trên nền navy
  static const heroMuted = Color(0xFFA9B6CC), heroLine = Color(0x1FFFFFFF);
  // Trạng thái: màu chữ + nền nhạt
  static const wait = Color(0xFFB4690E), waitBg = Color(0xFFFFF4E5); // chờ duyệt
  static const ok = Color(0xFF008A05), okBg = Color(0xFFE8F5E9); // đã duyệt
  static const warn = Color(0xFF222222), warnBg = Color(0xFFF0F0F0); // trả lại
  static const bad = Color(0xFFC13515), badBg = Color(0xFFFFF0EE); // từ chối
  static const done = Color(0xFF0B3D91), doneBg = Color(0xFFEAF1FE); // đã thanh toán
  static const draft = Color(0xFF6A6A6A), draftBg = Color(0xFFF7F7F7);
  static const green = ok;
  // Chữ cảnh báo (AI đọc, việc còn thiếu): cam, khác "trả lại" (đen)
  static const alert = Color(0xFFB4690E);
}

/// Nền navy chuyển màu (thanh tiêu đề, khung thương hiệu), như thanh bên của web.
const navyGradient = LinearGradient(
  // Ngang (sáng bên phải): thanh tiêu đề và phần tiền bên dưới nối liền không lộ vết
  begin: Alignment.centerRight,
  end: Alignment.centerLeft,
  colors: [C.navy2, C.navy, C.navyDeep],
  stops: [0, 0.45, 1],
);

/// Nút chính: xanh dương chuyển màu.
const blueGradient = LinearGradient(colors: [C.blue, Color(0xFF1A62E0), C.blue2]);

/// Bóng của thẻ chính.
const cardShadow = [BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 6))];

/// Bo góc: ô nhập, nút 8; thẻ, khung 12.
abstract final class R {
  static const ctl = 8.0, card = 12.0;
}

/// tông: [màu chữ, màu nền]
const tones = <String, (Color, Color)>{
  'draft': (C.draft, C.draftBg),
  'warn': (C.warn, C.warnBg),
  'wait': (C.wait, C.waitBg),
  'bad': (C.bad, C.badBg),
  'ok': (C.ok, C.okBg),
  'done': (C.done, C.doneBg),
  'vip': (Color(0xFF8A5A00), C.amberBg),
};

/// Mã hồ sơ: 81 -> "HS-00081".
String hsId(Object? id) => 'HS-${asInt(id).toString().padLeft(5, '0')}';

/// Mã phiếu chi: 7 -> "PC-00007".
String pcId(Object? id) => 'PC-${asInt(id).toString().padLeft(5, '0')}';
(Color, Color) tone(String t) => tones[t] ?? tones['draft']!;

// ---------- Icon nét 2px (y hệt sprite của web) ----------
const _icons = <String, String>{
  'check': '<path d="M20 6 9 17l-5-5"/>',
  'x': '<path d="M18 6 6 18M6 6l12 12"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'upload': '<path d="M12 16V4M7 9l5-5 5 5M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3"/>',
  'image': '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>',
  'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  'pin': '<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>',
  'alert': '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01"/>',
  'info': '<circle cx="12" cy="12" r="9"/><path d="M12 16v-4M12 8h.01"/>',
  'phone': '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .4 1.9.7 2.8a2 2 0 0 1-.5 2.1L8 9.9a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.8.7a2 2 0 0 1 1.7 2z"/>',
  'trash': '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>',
  'left': '<path d="m15 18-6-6 6-6"/>',
  'right': '<path d="m9 18 6-6-6-6"/>',
  'wallet': '<path d="M19 7V5a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2"/><path d="M3 6v12a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-3"/>',
  'spark': '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>',
  'receipt': '<path d="M5 3h14v18l-3-2-2 2-2-2-2 2-2-2-3 2z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
  'inbox': '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.5 5h13l3.5 7v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-6z"/>',
  'logout': '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
  'bank': '<path d="M3 21h18M5 21V10M19 21V10M9 21V10M15 21V10M2 10l10-6 10 6z"/>',
  'lock': '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  'send': '<path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/>',
  'book': '<path d="M4 4h6a2 2 0 0 1 2 2v14a2 2 0 0 0-2-2H4zM20 4h-6a2 2 0 0 0-2 2v14a2 2 0 0 1 2-2h6z"/>',
  'shield': '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m9 12 2 2 4-4"/>',
  'undo': '<path d="M9 14 4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/>',
  'ban': '<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>',
  'building': '<path d="M4 21V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v16M16 9h2a2 2 0 0 1 2 2v10M2 21h20M8 7h4M8 11h4M8 15h4"/>',
  'eye': '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  'play': '<path d="M7 4.5v15a1 1 0 0 0 1.5.86l12-7.5a1 1 0 0 0 0-1.72l-12-7.5A1 1 0 0 0 7 4.5z" fill="FILL"/>',
  'video': '<rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3.5v11L16 14"/>',
  'camera': '<path d="M3 8a1 1 0 0 1 1-1h3l2-3h6l2 3h3a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/><circle cx="12" cy="13" r="4"/>',
  'bolt': '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  'mark': '<path d="M5 12.5 10 17.5 19.5 7"/>',
  'user': '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
};

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class Ic extends StatelessWidget {
  const Ic(this.name, {super.key, this.size = 20, this.color = C.text, this.stroke = 2});
  final String name;
  final double size;
  final Color color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="${_hex(color)}" '
        'stroke-opacity="${color.a}" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">${(_icons[name] ?? '').replaceAll('FILL', _hex(color))}</svg>';
    return SvgPicture.string(svg, width: size, height: size);
  }
}

// ---------- Định dạng ----------
String money(num? n) {
  final v = (n ?? 0).round();
  final s = v.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '-' : ''}$sđ';
}

final _ts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?)?\s*(Z|[+-]\d{2}:?\d{2})?$');

/// Tách ngày giờ máy chủ: RFC 3339 ("2026-11-13T14:13:05+07:00") hoặc "YYYY-MM-DD HH:MM[:SS]".
/// Có múi giờ khác +07:00 thì đổi sang giờ Việt Nam. Trả [năm, tháng, ngày, giờ?, phút?].
List<String?>? _vnParts(String? s) {
  final t = (s ?? '').trim();
  final m = _ts.firstMatch(t);
  if (m == null) return null;
  final zone = m.group(6);
  if (zone != null && m.group(4) != null && zone != '+07:00' && zone != '+0700') {
    final dt = DateTime.tryParse(t);
    if (dt != null) {
      final v = dt.toUtc().add(const Duration(hours: 7));
      String p(int n) => n.toString().padLeft(2, '0');
      return ['${v.year}', p(v.month), p(v.day), p(v.hour), p(v.minute)];
    }
  }
  return [m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)];
}

/// "2026-11-13T14:13:05+07:00" hoặc "2026-11-06 12:54" -> "06/11/2026"
String vnDate(String? s) {
  final p = _vnParts(s);
  return p == null ? '' : '${p[2]}/${p[1]}/${p[0]}';
}

/// "2026-11-13T14:13:05+07:00" -> "14:13 13/11/2026"; "2026-11-06 12:54" -> "12:54 06/11/2026"
String vnTime(String? s) {
  final p = _vnParts(s);
  if (p == null) return s ?? '';
  return p[3] == null ? vnDate(s) : '${p[3]}:${p[4]} ${p[2]}/${p[1]}/${p[0]}';
}

String initials(String? name) {
  final w = (name ?? '?').trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  return (w.first[0] + (w.length > 1 ? w.last[0] : '')).toUpperCase();
}

int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String str(Object? v) => v == null ? '' : '$v';

// ---------- Kiểu chữ ----------
const _tab = [FontFeature.tabularFigures()];
const _monoFallback = ['monospace', 'Roboto Mono', 'Courier'];

abstract final class T {
  static const muted = TextStyle(color: C.muted, fontSize: 13, height: 1.4);
  static const secT = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.2, height: 1.3);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text);
  static const hint = TextStyle(fontSize: 12.5, color: C.muted, height: 1.4);
  static const body = TextStyle(fontSize: 15, color: C.text, height: 1.35);
  static const bold = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.1);
  /// Nhãn mục nhỏ in hoa (tiêu đề mục)
  static const formHead = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 0.6);
  /// Nhãn ô trong khung thông tin: 10px đậm, in hoa (viết sẵn chữ hoa)
  static const cap = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text, letterSpacing: 0.4);
  /// Số, tiền, giờ: chữ số đều cột
  static const num = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text, fontFeatures: _tab);
  /// Mã hồ sơ, toạ độ: phông mono
  static const mono = TextStyle(fontSize: 12.5, color: C.muted, fontFamily: 'monospace', fontFamilyFallback: _monoFallback, fontFeatures: _tab);
}

Future<Res?> push<Res>(BuildContext context, Widget page) => Navigator.of(context).push<Res>(MaterialPageRoute(builder: (_) => page));

// ---------- Mảnh giao diện ----------
class VtAppBar extends StatelessWidget {
  const VtAppBar({super.key, required this.title, this.sub, this.back = false, this.onBack, this.right});
  final String title;
  final String? sub;
  final bool back;
  final VoidCallback? onBack;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: const BoxDecoration(gradient: navyGradient),
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(spacing: 10, children: [
              if (back)
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: IconButton(
                    tooltip: 'Quay lại',
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon: const Ic('left', color: Colors.white, size: 24),
                  ),
                )
              else
                const Brand(size: 30),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                  if (sub != null && sub!.isNotEmpty)
                    Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.heroMuted, fontSize: 12.5)),
                ]),
              ),
              if (right != null) right!,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Logo: ô vàng góc vuông nhẹ + dấu tích navy.
class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.asset('assets/logo.png', width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium,
            semanticLabel: 'Vua Thầu'),
      );
}

/// primary: nút chính xanh dương chuyển màu (mỗi màn 1 nút), dark: nút navy, normal: nút trắng viền đen, danger: nút trắng chữ đỏ.
enum BtnKind { primary, dark, normal, danger }

class Btn extends StatelessWidget {
  const Btn(this.title, {super.key, this.icon, this.onPressed, this.kind = BtnKind.normal, this.disabled = false, this.busy = false});
  final String title;
  final String? icon;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final bool disabled, busy;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (C.blue, Colors.white, Colors.transparent),
      BtnKind.dark => (C.navy, Colors.white, C.navy),
      BtnKind.normal => (Colors.white, C.text, C.text),
      BtnKind.danger => (Colors.white, C.bad, C.line2),
    };
    final off = disabled || busy;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.ctl), side: BorderSide(color: border));
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          if (busy)
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
          else if (icon != null)
            Ic(icon!, color: fg, size: 18),
          Flexible(
            child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.1)),
          ),
        ]),
      ),
    );
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: kind == BtnKind.primary ? Colors.transparent : bg,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: kind == BtnKind.primary ? BoxDecoration(gradient: blueGradient, borderRadius: BorderRadius.circular(R.ctl)) : null,
          child: InkWell(borderRadius: BorderRadius.circular(R.ctl), onTap: off ? null : onPressed, child: body),
        ),
      ),
    );
  }
}

/// Khung trắng bo 12, viền mảnh, các con xếp dọc cách nhau [gap]. [raised]: đổ bóng (thẻ chính).
class Box extends StatelessWidget {
  const Box({super.key, required this.children, this.padding = const EdgeInsets.all(16), this.gap = 12, this.onTap, this.raised = false});
  final List<Widget> children;
  final EdgeInsets padding;
  final double gap;
  final VoidCallback? onTap;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: gap, children: children),
    );
    final card = Material(
      color: C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.card), side: const BorderSide(color: C.line2)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    if (!raised) return card;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.card), boxShadow: cardShadow),
      child: card,
    );
  }
}

/// Khung thông tin đóng viền kiểu Airbnb: các hàng, mỗi hàng 1 hoặc nhiều ô, ngăn bằng vạch 1px #b0b0b0.
class FieldBox extends StatelessWidget {
  const FieldBox({super.key, required this.rows, this.radius = 12, this.firstShaded = false});
  final List<List<Widget>> rows;
  final double radius;

  /// Hàng đầu nền xám nhạt (ô quan trọng nhất)
  final bool firstShaded;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(border: Border.all(color: C.field), borderRadius: BorderRadius.circular(radius)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              decoration: BoxDecoration(
                color: firstShaded && i == 0 ? C.soft : null,
                border: i > 0 ? const Border(top: BorderSide(color: C.field)) : null,
              ),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var k = 0; k < rows[i].length; k++)
                    Expanded(
                      child: Container(
                        decoration: k > 0 ? const BoxDecoration(border: Border(left: BorderSide(color: C.field))) : null,
                        child: rows[i][k],
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      );
}

/// 1 ô trong FieldBox: nhãn nhỏ in hoa + giá trị.
class FieldCell extends StatelessWidget {
  const FieldCell(this.label, this.value, {super.key, this.big = false, this.onTap, this.child});
  final String label, value;
  final bool big;
  final VoidCallback? onTap;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text(label.toUpperCase(), style: T.cap),
        child ??
            Text(value.isNotEmpty ? value : '—',
                style: big
                    ? const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.text, height: 1.3)
                    : const TextStyle(fontSize: 15, color: C.text, height: 1.35)),
      ]),
    );
    return onTap == null ? body : InkWell(onTap: onTap, child: body);
  }
}

/// Tiêu đề mục: chữ nhỏ in hoa, giãn chữ, màu phụ.
class Sec extends StatelessWidget {
  const Sec(this.title, {super.key, this.right});
  final String title;
  final String? right;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(title.toUpperCase(), style: T.formHead)),
          if (right != null) Text(right!, style: T.hint.copyWith(color: C.subtle)),
        ]),
      );
}

class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.ai = false,
    this.placeholder,
    this.keyboardType,
    this.obscure = false,
    this.multiline = false,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
    this.capitalization = TextCapitalization.none,
    this.formatters,
    this.autofill,
  });
  final String label;
  final TextEditingController controller;
  final String? hint, error, placeholder;
  final bool ai, obscure, multiline;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted, onChanged;
  final Widget? suffix;
  final TextCapitalization capitalization;
  final List<TextInputFormatter>? formatters;
  final Iterable<String>? autofill;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(R.ctl), borderSide: BorderSide(color: c, width: w));
    final err = error != null && error!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text(label.toUpperCase(), style: T.cap),
      TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: multiline ? TextInputType.multiline : keyboardType,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 5 : 1,
        textCapitalization: capitalization,
        inputFormatters: formatters,
        autofillHints: autofill,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 16, color: C.text),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          hintText: placeholder,
          hintStyle: const TextStyle(color: C.placeholder),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          suffixIcon: suffix,
          enabledBorder: b(err ? C.bad : C.field),
          focusedBorder: b(err ? C.bad : C.text, 1.5),
        ),
      ),
      if (err)
        Text(error!, style: T.hint.copyWith(color: C.bad))
      else if (ai)
        const Row(spacing: 6, children: [
          Ic('spark', size: 13, color: C.alert),
          Text('AI đọc từ ảnh, kiểm tra lại', style: TextStyle(fontSize: 12.5, color: C.alert)),
        ])
      else if (hint != null)
        Text(hint!, style: T.hint),
    ]);
  }
}

/// Nhãn trạng thái: viên thuốc bo tròn, chấm tròn 6px (hoặc icon) + chữ màu trạng thái trên nền nhạt.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.tone, this.icon});
  final String text, tone;
  final String? icon;
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = tones[tone] ?? tones['draft']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        if (icon != null)
          Ic(icon!, size: 12, color: fg)
        else
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.2))),
      ]),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Pill(cfg.statusLabel(status), tone: cfg.statusTone(status));
}

/// Thanh n ô: tiến độ gom đủ hồ sơ / đủ ảnh.
class Segs extends StatelessWidget {
  const Segs({super.key, required this.n, required this.total, this.dark = false});
  final int n, total;
  final bool dark;
  @override
  Widget build(BuildContext context) {
    final full = n >= total;
    return Semantics(
      label: '${n.clamp(0, total)} trên $total',
      child: Row(spacing: 4, children: [
        for (var k = 0; k < total; k++)
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: k < n ? (full ? C.green : C.blue) : (dark ? Colors.white.withValues(alpha: .18) : C.line),
              ),
            ),
          ),
      ]),
    );
  }
}

class Note extends StatelessWidget {
  const Note({super.key, required this.tone, required this.icon, required this.title, this.text, this.onTap});
  final String tone, icon, title;
  final String? text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = tones[tone]!;
    // Khung nhạt viền mảnh, vạch màu trạng thái bên trái
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.card), side: BorderSide(color: fg.withValues(alpha: .22))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: fg, width: 3))),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Ic(icon, color: fg, size: 18)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: fg)),
                if (text != null && text!.isNotEmpty) Text(text!, style: const TextStyle(color: C.text, fontSize: 13.5, height: 1.4)),
              ]),
            ),
            if (onTap != null) Padding(padding: const EdgeInsets.only(top: 1), child: Ic('right', color: fg, size: 16)),
          ]),
        ),
      ),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty({super.key, required this.icon, required this.title, required this.text, this.cta, this.onTap});
  final String icon, title, text;
  final String? cta;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(spacing: 8, children: [
          Container(
            width: 52,
            height: 52,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
            alignment: Alignment.center,
            child: Ic(icon, size: 24, color: C.navy3, stroke: 1.75),
          ),
          Text(title, style: T.secT, textAlign: TextAlign.center),
          Text(text, style: T.muted, textAlign: TextAlign.center),
          if (cta != null) Padding(padding: const EdgeInsets.only(top: 8), child: Btn(cta!, kind: BtnKind.primary, onPressed: onTap)),
        ]),
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key, this.err = '', this.retry});
  final String err;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: err.isNotEmpty
              ? Column(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
                  Text(err, style: T.muted, textAlign: TextAlign.center),
                  if (retry != null) Btn('Thử lại', onPressed: retry),
                ])
              : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: C.navy, strokeWidth: 2.5)),
        ),
      );
}

/// Phần tiền trên nền navy ở đầu màn Hồ sơ và Thu nhập.
/// Dời nội dung lên đè mép dưới phần navy (như marginTop: -32 của bản web).
class Lift extends StatelessWidget {
  const Lift({super.key, required this.child, this.by = 32});
  final Widget child;
  final double by;
  @override
  Widget build(BuildContext context) => Transform.translate(offset: Offset(0, -by), child: child);
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 44, this.color = C.soft, required this.child});
  final double size;
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(R.card)),
        alignment: Alignment.center,
        child: child,
      );
}

/// Ảnh từ máy chủ (cần token).
class NetPhoto extends StatelessWidget {
  const NetPhoto(this.url, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.alignment = Alignment.center});
  NetPhoto.id(int pid, {Key? key, BoxFit fit = BoxFit.cover, double? width, double? height})
      : this(photoUrl(pid), key: key, fit: fit, width: width, height: height);
  final String url;
  final BoxFit fit;
  final double? width, height;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => Image.network(
        url,
        headers: authHeaders(),
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) =>
            sync || frame != null ? child : Container(width: width, height: height, color: C.line),
        errorBuilder: (context, e, s) => Container(width: width, height: height, color: C.line, alignment: Alignment.center, child: const Ic('image', color: C.muted)),
      );
}

/// Hộp hỏi lại trước thao tác nguy hiểm. Trả true nếu bấm nút [ok].
Future<bool> confirm(BuildContext context, {required String title, String text = '', required String ok, String cancel = 'Huỷ', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: text.isEmpty ? null : Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok, style: TextStyle(color: danger ? C.bad : C.navy, fontWeight: FontWeight.w600))),
      ],
    ),
  );
  return r ?? false;
}

/// Dòng có thể bấm trong danh sách (đổi nền khi nhấn).
class Tap extends StatelessWidget {
  const Tap({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.top = false});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool top; // kẻ vạch phía trên
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          decoration: top ? const BoxDecoration(border: Border(top: BorderSide(color: C.line))) : null,
          padding: padding,
          child: child,
        ),
      );
}
