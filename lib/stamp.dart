// Dải chữ y hệt Timemark: vạch vàng + "Thứ Hai, 09 Tháng 11,2026 06:45", địa chỉ, toạ độ °N/°E ở góc trái;
// logo Vua Thầu + "100% Chân thực" ở góc phải; khiên + mã + "Vua Thầu Verified" chạy dọc mép phải.
// Chép từ stamp() của web (static/camera.js). Khung ngắm và ảnh chụp vẽ bằng CÙNG hàm này nên chụp ra đúng như thấy.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'lfile.dart';

class Pos {
  const Pos(this.lat, this.lng, this.acc);
  final double lat, lng, acc;
}

class StampData {
  const StampData(this.date, this.pos, this.addr, {this.brand = '', this.logo, this.scale = 1, this.badge = false});
  final DateTime date;
  final Pos? pos;
  final String addr;

  /// Tên công ty nhà thầu: có thì in dải chữ mới (thiết kế 24/11/2026) "Smartcons | ngày giờ / địa chỉ / GPS";
  /// trống (CTV): dải chữ kiểu Timemark như cũ.
  final String brand;

  /// Logo trên ảnh (màn "Logo trên ảnh"): logo công ty thay cho tên dạng chữ; cỡ (0.8 nhỏ / 1 vừa / 1.25 lớn);
  /// nhãn "Vua Thầu xác minh" góc trên phải.
  final ui.Image? logo;
  final double scale;
  final bool badge;
}

const _week = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật']; // DateTime.weekday: 1 = thứ Hai
String p2(int n) => n.toString().padLeft(2, '0');
const _maxSide = 1920; // như ảnh từ camera web: đủ nét, tải lên nhanh qua 4G
const _amber = Color(0xFFFFB51C);
String _deg(double v, String pos, String neg) => '${v.abs().toStringAsFixed(6)}°${v >= 0 ? pos : neg}';

/// Mã chỉ để hiển thị như Timemark (băm giờ + toạ độ), không ký số; xác thực thật là máy chủ đối chiếu GPS + giờ chụp.
String stampCode(StampData d) {
  final s = '${d.date.millisecondsSinceEpoch}|${d.pos?.lat ?? ''}|${d.pos?.lng ?? ''}';
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var h = 2166136261;
  final out = StringBuffer();
  for (var k = 0; k < 14; k++) {
    for (final c in '$s$k'.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
    }
    out.write(a[h % a.length]);
  }
  return out.toString();
}

TextPainter _tp(String s, double size, FontWeight w, Color color, double u) => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          fontWeight: w,
          color: color,
          shadows: [Shadow(color: const Color(0x99000000), offset: Offset(0, 0.1 * u), blurRadius: 0.7 * u)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

double _width(String s, double size, FontWeight w) => _tp(s, size, w, Colors.white, 0).width;

/// Vẽ chữ với y là đường chân chữ (baseline), như drawText của Skia/canvas web.
void _text(Canvas c, String s, double x, double y, double size, double u, {FontWeight w = FontWeight.w400, Color color = Colors.white}) {
  final tp = _tp(s, size, w, color, u);
  tp.paint(c, Offset(x, y - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
}

List<String> _wrap(String text, double size, double maxW, int maxLines) {
  final out = <String>[];
  var line = '';
  for (final w in text.split(' ')) {
    final t = line.isNotEmpty ? '$line $w' : w;
    if (_width(t, size, FontWeight.w400) <= maxW || line.isEmpty) {
      line = t;
      continue;
    }
    out.add(line);
    line = w;
  }
  out.add(line);
  if (out.length > maxLines) {
    out.removeRange(maxLines, out.length);
    var last = out[maxLines - 1];
    while (last.isNotEmpty && _width('$last…', size, FontWeight.w400) > maxW) {
      last = last.substring(0, last.length - 1);
    }
    out[maxLines - 1] = '$last…';
  }
  return out;
}

/// Dải chữ nhà thầu: logo / tên công ty bên trái | vạch dọc | thứ ngày giờ, địa chỉ, toạ độ bên phải, sát đáy ảnh;
/// nhãn "Vua Thầu xác minh" góc trên phải (màn Logo trên ảnh).
void _paintBrand(Canvas c, double W, double H, StampData d) {
  final u = math.min(W, H) / 100, t = d.date, x = 4.5 * u;
  final k = d.scale.clamp(0.6, 1.5);
  final maxB = 0.36 * W * k.clamp(0.8, 1.25);
  // logo: cao ~ khối thông tin (3-4 dòng) theo cỡ đã chọn, rộng không quá maxB
  final logo = d.logo;
  double lw = 0, lh0 = 0;
  if (logo != null && logo.width > 0 && logo.height > 0) {
    lh0 = 13.5 * u * k;
    lw = lh0 * logo.width / logo.height;
    if (lw > maxB) {
      lw = maxB;
      lh0 = lw * logo.height / logo.width;
    }
  }
  // tên công ty: to, đậm; dài quá thì xuống 2 hàng (góp ý 24/11), vẫn dài thì thu nhỏ chữ cho vừa
  var bs = 6.4 * u * k;
  var brand = logo != null ? <String>[] : _wrapBold(d.brand.trim(), bs, maxB);
  if (brand.length > 1) {
    bs = 5.0 * u * k; // 2 hàng: chữ nhỏ hơn 1 chút cho cân với khối thông tin
    brand = _wrapBold(d.brand.trim(), bs, maxB);
  }
  var bw = logo != null ? lw : brand.map((l) => _width(l, bs, FontWeight.w800)).fold<double>(0, math.max);
  if (logo == null && bw > maxB) {
    bs *= maxB / bw;
    bw = maxB;
  }
  final dx = x + bw + 3.2 * u, rx = dx + 3.2 * u, maxW = W - rx - 3.5 * u;
  var fs = 3.3 * u;
  final date = '${_week[t.weekday - 1]}, ${p2(t.day)} Tháng ${t.month}, ${t.year} ${p2(t.hour)}:${p2(t.minute)}';
  final gps = d.pos != null ? '${_deg(d.pos!.lat, 'N', 'S')}, ${_deg(d.pos!.lng, 'E', 'W')}' : 'Đang lấy vị trí GPS…';
  final widest = math.max(_width(date, fs, FontWeight.w500), _width(gps, fs, FontWeight.w500));
  if (widest > maxW) fs *= maxW / widest;
  final lh = fs * 1.32;
  final lines = [date, if (d.addr.isNotEmpty) ..._wrap(d.addr, fs, maxW, 2), gps];
  final bottom = H - 4.2 * u; // đường chân chữ dòng cuối
  final top = bottom - (lines.length - 1) * lh - fs;
  for (var i = 0; i < lines.length; i++) {
    _text(c, lines[i], rx, bottom - (lines.length - 1 - i) * lh, fs, u, w: FontWeight.w500);
  }
  // vạch dọc ngăn logo / tên công ty và thông tin
  c.drawRect(Rect.fromLTWH(dx, top - 0.6 * u, math.max(1, 0.28 * u), bottom - top + 1.6 * u), Paint()..color = const Color(0xD9FFFFFF));
  final mid = (top + bottom) / 2 + 0.5 * u;
  if (logo != null) {
    c.drawImageRect(logo, Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()), Rect.fromLTWH(x, mid - lh0 / 2, lw, lh0),
        Paint()..filterQuality = FilterQuality.medium);
  } else {
    // tên công ty (1 hoặc 2 hàng) canh giữa theo chiều cao khối thông tin
    final blh = bs * 1.15;
    final first = mid - 0.5 * u + bs * 0.36 - (brand.length - 1) * blh / 2;
    for (var i = 0; i < brand.length; i++) {
      _text(c, brand[i], x, first + i * blh, bs, u, w: FontWeight.w800);
    }
  }
  if (d.badge) _badge(c, W, u);
}

/// Nhãn "✓ Vua Thầu xác minh" góc trên phải ảnh (chủ nhà tin ảnh hơn khi thấy nhãn này).
void _badge(Canvas c, double W, double u) {
  const label = '✓ Vua Thầu xác minh';
  final fs = 2.6 * u, w = _width(label, fs, FontWeight.w700) + 3.2 * u, h = fs + 2.2 * u;
  final r = RRect.fromRectAndRadius(Rect.fromLTWH(W - 2.5 * u - w, 2.5 * u, w, h), Radius.circular(h / 2));
  c.drawRRect(r, Paint()..color = const Color(0x8C000000));
  _text(c, label, r.left + 1.6 * u, r.top + h / 2 + fs * 0.36, fs, u, w: FontWeight.w700, color: const Color(0xFFFFB81C));
}

/// Chia tên công ty (chữ đậm) thành tối đa 2 hàng vừa maxW, ngắt ở dấu cách gần giữa nhất.
List<String> _wrapBold(String s, double size, double maxW) {
  if (_width(s, size, FontWeight.w800) <= maxW || !s.contains(' ')) return [s];
  final words = s.split(' ');
  var best = [s];
  var bestW = double.infinity;
  for (var i = 1; i < words.length; i++) {
    final a = words.sublist(0, i).join(' '), b = words.sublist(i).join(' ');
    final w = math.max(_width(a, size, FontWeight.w800), _width(b, size, FontWeight.w800));
    if (w < bestW) {
      bestW = w;
      best = [a, b];
    }
  }
  return best;
}

void paintStamp(Canvas c, double W, double H, StampData d) {
  if (d.brand.trim().isNotEmpty || d.logo != null) {
    // nền tối mờ dưới đáy cho chữ trắng dễ đọc trên ảnh sáng
    final u0 = math.min(W, H) / 100;
    final r = Rect.fromLTWH(0, H - 26 * u0, W, 26 * u0);
    c.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x8C000000)]).createShader(r));
    _paintBrand(c, W, H, d);
    return;
  }
  final u = math.min(W, H) / 100, x = 5.7 * u, t = d.date;

  // Góc trái, từ dưới lên: toạ độ / địa chỉ / thứ, ngày giờ; vạch vàng chạy suốt cạnh trái
  final fs = 3.4 * u, lh = 4.45 * u;
  final addr = d.addr.isNotEmpty ? _wrap(d.addr, fs, 0.68 * W - x, 3) : <String>[];
  var y = H - 3.5 * u;
  _text(c, d.pos != null ? '${_deg(d.pos!.lat, 'N', 'S')}, ${_deg(d.pos!.lng, 'E', 'W')}' : 'Đang lấy vị trí GPS…', x, y, fs, u);
  if (addr.isNotEmpty) {
    y -= 7.6 * u + (addr.length - 1) * lh;
    for (var k = 0; k < addr.length; k++) {
      _text(c, addr[k], x, y + k * lh, fs, u);
    }
    y -= 7.1 * u;
  } else {
    y -= 7.4 * u;
  }
  _text(c, '${_week[t.weekday - 1]}, ${p2(t.day)} Tháng ${t.month},${t.year} ${p2(t.hour)}:${p2(t.minute)}', x, y, fs, u);
  final top = y - 3.05 * u;
  c.drawRect(Rect.fromLTWH(3 * u, top, 0.5 * u, H - 2.3 * u - top), Paint()..color = _amber);

  // Góc phải: "Vua" vàng + "Thầu" trắng, dưới là "100% Chân thực"
  final r = W - 1.7 * u, ls = 3.3 * u, ss = 2.2 * u, tw = _width('Thầu', ls, FontWeight.w700);
  _text(c, 'Thầu', r - tw, H - 5.1 * u, ls, u, w: FontWeight.w700);
  _text(c, 'Vua ', r - tw - _width('Vua ', ls, FontWeight.w700), H - 5.1 * u, ls, u, w: FontWeight.w700, color: _amber);
  _text(c, '100% Chân thực', r - _width('100% Chân thực', ss, FontWeight.w400), H - 2.1 * u, ss, u, color: const Color(0xE0FFFFFF));

  // Mép phải, chữ dọc đọc từ dưới lên: khiên + mã + "Vua Thầu Verified"
  final vs = 2.2 * u, s = 2.1 * u, code = stampCode(d);
  const white92 = Color(0xEBFFFFFF);
  c.save();
  c.translate(W - 0.85 * u, 0.6 * H);
  c.rotate(-math.pi / 2);
  c.save();
  c.translate(0, -0.95 * s);
  c.scale(s, s);
  final shield = Path()
    ..moveTo(0.5, 0.06)
    ..lineTo(0.88, 0.2)
    ..lineTo(0.88, 0.5)
    ..cubicTo(0.88, 0.74, 0.7, 0.9, 0.5, 0.97)
    ..cubicTo(0.3, 0.9, 0.12, 0.74, 0.12, 0.5)
    ..lineTo(0.12, 0.2)
    ..close()
    ..moveTo(0.32, 0.52)
    ..lineTo(0.46, 0.66)
    ..lineTo(0.7, 0.4);
  c.drawPath(
    shield,
    Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = white92,
  );
  c.restore();
  _text(c, code, s + 0.8 * u, 0, vs, u, color: white92);
  _text(c, 'Vua Thầu Verified', s + 2.2 * u + _width(code, vs, FontWeight.w400), 0, vs, u, color: white92);
  c.restore();
}

/// Vẽ dải chữ đè lên khung ngắm camera.
class StampPainter extends CustomPainter {
  const StampPainter(this.d);
  final StampData d;
  @override
  void paint(Canvas canvas, Size size) => paintStamp(canvas, size.width, size.height, d);
  @override
  bool shouldRepaint(StampPainter old) =>
      old.d.date.minute != d.date.minute || old.d.pos?.lat != d.pos?.lat || old.d.pos?.lng != d.pos?.lng || old.d.addr != d.addr || old.d.brand != d.brand ||
      old.d.logo != d.logo || old.d.scale != d.scale || old.d.badge != d.badge;
}

// JPEG 85 (trước là 90): mắt thường không thấy khác, file nhẹ hơn ~25% (mạng yếu ở tỉnh tải lên nhanh hơn)
Uint8List _encode((Uint8List, int, int) a) => _encodeQ((a.$1, a.$2, a.$3, 85));

Uint8List _encodeQ((Uint8List, int, int, int) a) {
  final im = img.Image.fromBytes(width: a.$2, height: a.$3, bytes: a.$1.buffer, numChannels: 4);
  return img.encodeJpg(im, quality: a.$4);
}

/// Cạnh dài bản thu nhỏ gửi đi kiểm (AI đọc được giờ, địa chỉ, bảng hiệu; nhẹ ~5 lần ảnh gốc)
const checkSide = 1280;

/// Bản thu nhỏ của ảnh đã in chữ để gửi AI kiểm (mạng yếu: ~150KB thay vì ~800KB) + sha256 của ảnh gốc
/// (máy chủ lưu kết quả theo ảnh gốc: lúc nộp không đọc lại). Bản web: null (gửi ảnh gốc như cũ).
Future<(String, String)?> checkCopy(String path) async {
  if (kIsWeb) return null;
  final bytes = await readLocal(path);
  final sha = sha256.convert(bytes).toString();
  final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buf);
  final k = math.min(1.0, checkSide / math.max(desc.width, desc.height));
  final codec = await desc.instantiateCodec(targetWidth: math.max(1, (desc.width * k).round()), targetHeight: math.max(1, (desc.height * k).round()));
  final im = (await codec.getNextFrame()).image;
  final w = im.width, h = im.height;
  final rgba = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
  im.dispose();
  codec.dispose();
  desc.dispose();
  buf.dispose();
  if (rgba == null) return null;
  final jpg = await compute(_encodeQ, (rgba.buffer.asUint8List(), w, h, 75));
  return (await saveTemp(jpg, 'kiem-${DateTime.now().microsecondsSinceEpoch}.jpg'), sha);
}

/// Ảnh vừa chụp -> thu về tối đa 1920px, in dải chữ, lưu JPEG vào bộ nhớ tạm. Trả đường dẫn file mới.
Future<String> stampPhoto(String path, StampData d) async {
  final codec = await ui.instantiateImageCodec(await readLocal(path));
  final pic = (await codec.getNextFrame()).image;
  final k = math.min(1.0, _maxSide / math.max(pic.width, pic.height));
  // App chỉ chụp dọc (khoá xoay). Ảnh ra NGANG (máy không xoay theo EXIF): xoay 90° theo chiều kim đồng hồ cho dọc lại.
  final turn = !kIsWeb && pic.width > pic.height;
  final sw = (pic.width * k).round(), sh = (pic.height * k).round();
  final W = turn ? sh : sw, H = turn ? sw : sh;

  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.save();
  if (turn) {
    c.translate(W.toDouble(), 0);
    c.rotate(math.pi / 2);
  }
  c.drawImageRect(pic, Rect.fromLTWH(0, 0, pic.width.toDouble(), pic.height.toDouble()), Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
      Paint()..filterQuality = FilterQuality.medium);
  c.restore();
  paintStamp(c, W.toDouble(), H.toDouble(), d);
  final out = await rec.endRecording().toImage(W, H);
  pic.dispose();
  final rgba = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  out.dispose();
  if (rgba == null) throw Exception('máy không đủ bộ nhớ để in chữ lên ảnh');

  final jpg = await compute(_encode, (rgba.buffer.asUint8List(), W, H));
  final saved = await saveTemp(jpg, 'vuathau-${d.date.millisecondsSinceEpoch}.jpg');
  deleteLocal(path);
  return saved;
}
