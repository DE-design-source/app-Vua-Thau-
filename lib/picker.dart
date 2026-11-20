// Khối giao diện dùng chung cho ảnh / video: ô nét đứt chọn tệp, lưới ảnh, nút xoá, thanh tiến độ.
// (Chọn ảnh có sẵn để nộp đã bỏ 20/11/2026: ảnh hồ sơ chỉ chụp bằng camera Vua Thầu.)
import 'package:flutter/material.dart';

import 'ui.dart';

/// Ô nét đứt "chọn ảnh".
class DropZone extends StatelessWidget {
  const DropZone({super.key, required this.onTap, required this.title, required this.sub});
  final VoidCallback? onTap;
  final String title, sub;
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _Dash(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(R.card),
            splashColor: C.amberBg,
            highlightColor: C.amberBg,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(spacing: 4, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                  const Ic('upload', color: C.navy, size: 18),
                  Flexible(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.navy))),
                ]),
                Text(sub, textAlign: TextAlign.center, style: T.hint.copyWith(color: C.subtle)),
              ]),
            ),
          ),
        ),
      );
}

class _Dash extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(R.card));
    canvas.drawRRect(r, Paint()..color = Colors.white);
    final path = Path()..addRRect(r.deflate(1));
    final paint = Paint()
      ..color = C.field
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dash old) => false;
}

/// Lưới 3 cột ảnh vuông.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (final c in children) ClipRRect(borderRadius: BorderRadius.circular(R.ctl), child: ColoredBox(color: C.soft, child: c))],
      );
}

/// Nút vuông nhỏ xoá/bỏ ở góc phải trên của ô ảnh.
class DelBtn extends StatelessWidget {
  const DelBtn({super.key, required this.icon, required this.label, this.onTap});
  final String icon, label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Positioned(
        top: 4,
        right: 4,
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: C.text.withValues(alpha: .72), borderRadius: BorderRadius.circular(4)),
              alignment: Alignment.center,
              child: Ic(icon, color: Colors.white, size: 15),
            ),
          ),
        ),
      );
}

class Progress extends StatelessWidget {
  const Progress({super.key, required this.pct, required this.doneText});
  final double pct;
  final String doneText;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: LinearProgressIndicator(value: pct, minHeight: 4, color: C.amber, backgroundColor: C.line),
        ),
        Text(pct < 1 ? 'Đang tải lên ${(pct * 100).round()}%' : doneText, style: T.muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]);
}
