// Dải chữ y hệt Timemark: vạch vàng + "Thứ Hai, 09 Tháng 11,2026 06:45", địa chỉ, toạ độ °N/°E ở góc trái;
// logo Vua Thầu + "100% Chân thực" ở góc phải; khiên + mã + "Vua Thầu Verified" chạy dọc mép phải.
// Chép từ stamp() của web (static/camera.js). Khung ngắm và ảnh chụp vẽ bằng CÙNG hàm này nên chụp ra đúng như thấy.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'lfile.dart';

class Pos {
  const Pos(this.lat, this.lng, this.acc);
  final double lat, lng, acc;
}

class StampData {
  const StampData(this.date, this.pos, this.addr);
  final DateTime date;
  final Pos? pos;
  final String addr;
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

void paintStamp(Canvas c, double W, double H, StampData d) {
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
      old.d.date.minute != d.date.minute || old.d.pos?.lat != d.pos?.lat || old.d.pos?.lng != d.pos?.lng || old.d.addr != d.addr;
}

Uint8List _encode((Uint8List, int, int) a) {
  final im = img.Image.fromBytes(width: a.$2, height: a.$3, bytes: a.$1.buffer, numChannels: 4);
  return img.encodeJpg(im, quality: 90);
}

/// Ảnh vừa chụp -> thu về tối đa 1920px, in dải chữ, lưu JPEG vào bộ nhớ tạm. Trả đường dẫn file mới.
Future<String> stampPhoto(String path, StampData d) async {
  final codec = await ui.instantiateImageCodec(await readLocal(path));
  final pic = (await codec.getNextFrame()).image;
  final k = math.min(1.0, _maxSide / math.max(pic.width, pic.height));
  final W = (pic.width * k).round(), H = (pic.height * k).round();

  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawImageRect(pic, Rect.fromLTWH(0, 0, pic.width.toDouble(), pic.height.toDouble()), Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()),
      Paint()..filterQuality = FilterQuality.medium);
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
