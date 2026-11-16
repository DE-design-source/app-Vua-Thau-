// Giao diện dùng chung, cùng màu và icon với bản web (static/app.css, templates/_ui.html).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';

abstract final class C {
  static const navy = Color(0xFF001C33), navy2 = Color(0xFF0B2F4F), navy3 = Color(0xFF164672);
  static const amber = Color(0xFFFFB51C), amberBg = Color(0xFFFFF7E3), heroMuted = Color(0xFFA9BBCE);
  static const bg = Color(0xFFF2F4F7), card = Colors.white, text = Color(0xFF101828), muted = Color(0xFF5B6878), line = Color(0xFFE4E7EC);
  static const ok = Color(0xFF067647), okBg = Color(0xFFECFDF3), warn = Color(0xFFB54708), warnBg = Color(0xFFFFFAEB);
  static const bad = Color(0xFFB42318), badBg = Color(0xFFFEF3F2), wait = Color(0xFF175CD3), waitBg = Color(0xFFEFF8FF);
  static const soft = Color(0xFFE6EDF5), green = Color(0xFF12B76A), placeholder = Color(0xFF98A2B3);
}

/// tông: [màu chữ, màu nền]
const tones = <String, (Color, Color)>{
  'draft': (Color(0xFF475467), Color(0xFFF2F4F7)),
  'warn': (C.warn, C.warnBg),
  'wait': (C.wait, C.waitBg),
  'bad': (C.bad, C.badBg),
  'ok': (C.ok, C.okBg),
  'done': (Color(0xFF0B2F4F), Color(0xFFE6EDF5)),
};
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
        'stroke-opacity="${color.a}" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">${_icons[name] ?? ''}</svg>';
    return SvgPicture.string(svg, width: size, height: size);
  }
}

// ---------- Định dạng ----------
String money(num? n) {
  final v = (n ?? 0).round();
  final s = v.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '-' : ''}$sđ';
}

/// "2026-11-06 12:54:53" -> "06/11/2026"
String vnDate(String? s) => s != null && s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}' : '';

/// "2026-11-06 12:54:53" -> "12:54 06/11/2026"
String vnTime(String? s) => s != null && s.length >= 16 ? '${s.substring(11, 16)} ${vnDate(s)}' : (s ?? '');

String initials(String? name) {
  final w = (name ?? '?').trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  return (w.first[0] + (w.length > 1 ? w.last[0] : '')).toUpperCase();
}

int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String str(Object? v) => v == null ? '' : '$v';

// ---------- Kiểu chữ ----------
abstract final class T {
  static const muted = TextStyle(color: C.muted, fontSize: 13, height: 1.4);
  static const secT = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.text);
  static const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text);
  static const hint = TextStyle(fontSize: 13, color: C.muted, height: 1.4);
  static const body = TextStyle(fontSize: 15, color: C.text);
  static const bold = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.text);
  static const formHead = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 0.5);
}

Future<R?> push<R>(BuildContext context, Widget page) => Navigator.of(context).push<R>(MaterialPageRoute(builder: (_) => page));

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
        color: C.navy,
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
                const Brand(size: 34),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  if (sub != null && sub!.isNotEmpty)
                    Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.heroMuted, fontSize: 13)),
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

/// Logo: ô vàng + dấu tích navy.
class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(size * 0.29)),
        alignment: Alignment.center,
        child: Ic('mark', color: C.navy, size: size * 0.58, stroke: 3),
      );
}

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
      BtnKind.primary => (C.amber, C.navy, C.amber),
      BtnKind.dark => (C.navy, Colors.white, C.navy),
      BtnKind.normal => (Colors.white, C.text, C.line),
      BtnKind.danger => (Colors.white, C.bad, C.line),
    };
    final off = disabled || busy;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: off ? null : onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                if (busy)
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                else if (icon != null)
                  Ic(icon!, color: fg, size: 18),
                Flexible(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ trắng bo góc, các con xếp dọc cách nhau [gap].
class Box extends StatelessWidget {
  const Box({super.key, required this.children, this.padding = const EdgeInsets.all(16), this.gap = 12, this.onTap});
  final List<Widget> children;
  final EdgeInsets padding;
  final double gap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: gap, children: children),
    );
    return Material(
      color: C.card,
      elevation: 1,
      shadowColor: const Color(0x30101828),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class Sec extends StatelessWidget {
  const Sec(this.title, {super.key, this.right});
  final String title;
  final String? right;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(title, style: T.secT)),
          if (right != null) Text(right!, style: T.muted),
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
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
    final err = error != null && error!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text(label, style: T.label),
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
          enabledBorder: b(err ? C.bad : const Color(0xFFD0D5DD)),
          focusedBorder: b(err ? C.bad : C.navy3, 1.6),
        ),
      ),
      if (err)
        Text(error!, style: T.hint.copyWith(color: C.bad))
      else if (ai)
        const Row(spacing: 6, children: [
          Ic('spark', size: 14, color: C.warn),
          Text('AI đọc từ ảnh, kiểm tra lại', style: TextStyle(fontSize: 13, color: C.warn)),
        ])
      else if (hint != null)
        Text(hint!, style: T.hint),
    ]);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.tone, this.icon});
  final String text, tone;
  final String? icon;
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = tones[tone] ?? tones['draft']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        if (icon != null) Ic(icon!, size: 13, color: fg),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
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
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: k < n ? (full ? C.green : C.amber) : (dark ? Colors.white.withValues(alpha: .18) : C.line),
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
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: fg.withValues(alpha: .2))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Ic(icon, color: fg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                if (text != null && text!.isNotEmpty) Text(text!, style: const TextStyle(color: C.text, fontSize: 14, height: 1.4)),
              ]),
            ),
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
            width: 64,
            height: 64,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: const BoxDecoration(color: C.soft, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Ic(icon, size: 28, color: C.navy3),
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
              : const CircularProgressIndicator(color: C.navy),
        ),
      );
}

/// Phần tiền trên nền navy ở đầu màn Hồ sơ và Thu nhập.
class MoneyHero extends StatelessWidget {
  const MoneyHero({super.key, required this.label, required this.amount, required this.stats});
  final String label;
  final num amount;
  final List<(String, num)> stats;
  @override
  Widget build(BuildContext context) => Container(
        color: C.navy,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 44),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Row(spacing: 6, children: [
            const Ic('wallet', color: C.heroMuted, size: 16),
            Text(label, style: const TextStyle(color: C.heroMuted, fontSize: 14)),
          ]),
          Text(money(amount), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          Row(spacing: 10, children: [
            for (final (k, v) in stats)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(k, style: const TextStyle(color: C.heroMuted, fontSize: 13)),
                    Text(money(v), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
        ]),
      );
}

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
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok, style: TextStyle(color: danger ? C.bad : C.navy, fontWeight: FontWeight.w700))),
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
