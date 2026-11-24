// AI kiểm từng ảnh ngay lúc vừa chụp/chọn (POST /photos/check), chưa đưa vào hồ sơ: giờ chụp, vị trí, ảnh trùng, có phải công trình.
// Máy chủ lưu kết quả theo file: lúc tải lên đúng file đó thì không đọc lại, không tốn thêm.
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'lfile.dart';
import 'stamp.dart' show checkCopy;
import 'ui.dart';

enum CheckState { dang, ok, bad, loi }

class Check {
  const Check(this.state, this.text);
  final CheckState state;
  final String text;
}

/// Kiểm lần lượt từng ảnh (mạng yếu: không chia băng thông cho nhiều ảnh cùng lúc, ảnh đầu có kết quả sớm), gửi
/// bản thu nhỏ (stamp.checkCopy) kèm sha256 ảnh gốc. Bấm tải lên: stop() bỏ các ảnh chưa kiểm (máy chủ kiểm lúc nộp).
class Checks extends ChangeNotifier {
  final Map<String, Check> m = {};
  bool _dead = false, _running = false;
  final _queue = <Future<void> Function()>[];

  Check? operator [](String path) => m[path];

  void _put(String path, Check c) {
    if (_dead) return;
    m[path] = c;
    notifyListeners();
  }

  void run(String path, {Object? meta, String name = 'anh.jpg', String mime = 'image/jpeg'}) {
    _put(path, const Check(CheckState.dang, 'Chờ kiểm…'));
    _queue.add(() => _check(path, meta, name, mime));
    _pump();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    while (_queue.isNotEmpty && !_dead) {
      await _queue.removeAt(0)();
    }
    _running = false;
  }

  Future<void> _check(String path, Object? meta, String name, String mime) async {
    if (m[path]?.state != CheckState.dang) return; // đã bỏ (stop)
    _put(path, const Check(CheckState.dang, 'AI đang kiểm tra…'));
    (String, String)? small;
    if (mime == 'image/jpeg') {
      try {
        small = await checkCopy(path);
      } catch (_) {
        small = null; // không thu nhỏ được: gửi ảnh gốc
      }
    }
    try {
      final j = await upload('/photos/check', [UpFile('file', small?.$1 ?? path, name, mime)],
          fields: {if (meta != null) 'meta': jsonEncode(meta), if (small != null) 'sha': small.$2});
      final problems = (j['problems'] as List?)?.map((e) => '$e').toList() ?? const [];
      _put(
          path,
          problems.isNotEmpty
              ? Check(CheckState.bad, problems.join(' · '))
              : Check(CheckState.ok, j['ai'] == true ? 'Đạt' : 'Đạt, AI xem lại khi tải lên'));
    } catch (_) {
      _put(path, const Check(CheckState.loi, 'Chưa kiểm được, sẽ kiểm khi tải lên'));
    } finally {
      if (small != null) deleteLocal(small.$1);
    }
  }

  /// Bấm tải lên: bỏ các ảnh chưa kiểm (dồn mạng cho lượt tải lên; máy chủ kiểm lúc nộp).
  void stop() {
    _queue.clear();
    for (final e in m.entries.toList()) {
      if (e.value.state == CheckState.dang && e.value.text == 'Chờ kiểm…') {
        _put(e.key, const Check(CheckState.loi, 'Kiểm khi tải lên'));
      }
    }
  }

  /// "4 đạt · 1 chưa đạt · 1 đang kiểm" cho các ảnh đang chờ tải lên.
  String tally(List<String> paths) {
    int n(CheckState s) => paths.where((p) => m[p]?.state == s).length;
    return [
      if (n(CheckState.ok) > 0) '${n(CheckState.ok)} đạt',
      if (n(CheckState.bad) > 0) '${n(CheckState.bad)} chưa đạt',
      if (n(CheckState.dang) > 0) '${n(CheckState.dang)} đang kiểm',
    ].join(' · ');
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }
}

/// Nhãn kết quả nằm ở đáy ô ảnh.
class CheckBadge extends StatelessWidget {
  const CheckBadge(this.c, {super.key});
  final Check? c;
  @override
  Widget build(BuildContext context) {
    final c = this.c;
    if (c == null) return const SizedBox.shrink();
    final (fg, bg) = switch (c.state) {
      CheckState.ok => (C.ok, C.okBg),
      CheckState.bad => (C.bad, C.badBg),
      _ => (C.muted, C.bg),
    };
    return Positioned(
      left: 4,
      right: 4,
      bottom: 4,
      child: Semantics(
        label: c.text,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: fg.withValues(alpha: .25))),
          child: Row(spacing: 4, children: [
            if (c.state == CheckState.dang)
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: C.navy))
            else
              Ic(c.state == CheckState.ok ? 'check' : 'alert', color: fg, size: 13),
            Expanded(
              child: Text(c.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
            ),
          ]),
        ),
      ),
    );
  }
}
