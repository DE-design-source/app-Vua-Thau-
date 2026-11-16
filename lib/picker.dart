// Chọn ảnh có sẵn trong máy (ảnh Timemark...), xem trước, bỏ bớt, tải lên có báo %. Dùng ở Nộp ảnh và trong hồ sơ.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'check.dart';
import 'lfile.dart';
import 'toast.dart';
import 'ui.dart';

const _limit = 20 * 1024 * 1024;

class PhotoPicker extends StatefulWidget {
  const PhotoPicker({super.key, required this.path, required this.have, required this.valid, required this.title, required this.onUploaded});
  final String path, title;
  final int have, valid;
  /// Kết quả tải lên: {message, messages, house_id | added}
  final void Function(Json data) onUploaded;
  @override
  State<PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<PhotoPicker> {
  List<XFile> files = [];
  double? pct;
  String err = '';
  final checks = Checks();

  int get room => cfg.maxPhotos - widget.have;

  @override
  void initState() {
    super.initState();
    checks.addListener(_tick);
  }

  void _tick() => setState(() {});

  @override
  void dispose() {
    checks.removeListener(_tick);
    checks.dispose();
    super.dispose();
  }

  static String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> pick() async {
    final left = room - files.length;
    if (left <= 0) {
      setState(() => err = 'Mỗi hồ sơ tối đa ${cfg.maxPhotos} ảnh.');
      return;
    }
    List<XFile> got;
    try {
      final p = ImagePicker();
      got = left >= 2 ? await p.pickMultiImage(limit: left) : [if (await p.pickImage(source: ImageSource.gallery) case final x?) x];
    } catch (e) {
      toast('Không mở được thư viện ảnh: $e');
      return;
    }
    if (got.isEmpty) return;
    final big = <XFile>[];
    for (final a in got) {
      if (await localLength(a.path) > _limit) big.add(a);
    }
    final all = [...files, ...got.where((a) => !big.contains(a) && !files.any((x) => x.path == a.path))];
    final keep = all.take(room).toList();
    for (final a in keep.where((a) => !files.contains(a))) {
      checks.run(a.path, name: a.name, mime: _mime(a.name));
    }
    setState(() {
      err = [
        if (big.isNotEmpty) '${big.length} ảnh quá 20 MB, đã bỏ',
        if (all.length > room) 'Mỗi hồ sơ tối đa ${cfg.maxPhotos} ảnh, đã bỏ bớt ảnh thừa',
      ].join('. ');
      files = keep;
    });
  }

  Future<void> send() async {
    setState(() {
      err = '';
      pct = 0;
    });
    try {
      final j = await upload(
        widget.path,
        [for (var k = 0; k < files.length; k++) UpFile('files', files[k].path, files[k].name.isNotEmpty ? files[k].name : 'anh-${k + 1}.jpg', _mime(files[k].name))],
        onProgress: (p) {
          if (mounted) setState(() => pct = p);
        },
      );
      toast(msgsOf(j));
      if (mounted) setState(() => files = []);
      widget.onUploaded(j);
    } catch (e) {
      if (mounted) setState(() => err = errMsg(e));
    } finally {
      if (mounted) setState(() => pct = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.valid + files.length;
    final sum = checks.tally(files.map((a) => a.path).toList());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      DropZone(
        onTap: pct == null ? pick : null,
        title: widget.title,
        sub: 'Còn thêm được ${room - files.length} ảnh · JPG/PNG, mỗi ảnh dưới 20MB',
      ),
      if (files.isNotEmpty) ...[
        PhotoGrid(children: [
          for (var k = 0; k < files.length; k++)
            Stack(fit: StackFit.expand, children: [
              localImage(files[k].path, fit: BoxFit.cover, cacheWidth: 400),
              CheckBadge(checks[files[k].path]),
              DelBtn(icon: 'x', label: 'Bỏ ảnh ${k + 1}', onTap: pct == null ? () => setState(() => files.removeAt(k)) : null),
            ]),
        ]),
        Text(
          '${files.length} ảnh${sum.isNotEmpty ? ' (AI: $sum)' : ''}. '
          '${total < cfg.minPhotos ? 'Cần ít nhất ${cfg.minPhotos} ảnh đạt, có thể chọn thêm hoặc bổ sung sau.' : 'Nếu ${widget.have > 0 ? 'các ảnh mới' : 'tất cả'} đều đạt: ${money(cfg.payFor(total.clamp(0, cfg.maxPhotos)))}.'}',
          style: T.muted,
        ),
      ],
      if (pct != null) Progress(pct: pct!, doneText: 'Đã tải xong. Đang kiểm tra giờ chụp, vị trí, ảnh trùng…'),
      if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.bad, fontSize: 14)),
      if (files.isNotEmpty) Btn('Tải lên ${files.length} ảnh', icon: 'upload', kind: BtnKind.dark, onPressed: send, busy: pct != null),
    ]);
  }
}

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
