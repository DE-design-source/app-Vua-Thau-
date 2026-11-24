// Hỏi đánh giá app (góp ý 25/11/2026, "giống Claude hay hỏi"): tải lên đủ 30 ảnh thì hỏi 1-5 sao + góp ý.
// Máy chủ đếm ảnh và quyết định lúc hỏi (GET /feedback/ask): bấm "Để sau" thì hỏi lại 1 lần khi đủ 60 ảnh,
// đánh giá xong thì thôi. App hỏi khi mở app, và khi quay về màn chính sau lần tải ảnh lên.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';
import 'toast.dart';
import 'ui.dart';

bool _due = false, _showing = false;

/// Sau khi tải ảnh lên: hỏi máy chủ đã tới lúc chưa (hộp hỏi hiện khi về màn chính: showRatingIfDue).
Future<void> checkRating() async {
  try {
    final j = await api('/feedback/ask');
    if (j['ask'] == true) _due = true;
  } catch (_) {/* không hỏi được thì thôi */}
}

/// Mở app: hỏi máy chủ rồi hiện luôn nếu tới lúc (chờ màn chính dựng xong).
Future<void> checkAndShowRating(BuildContext context) async {
  await checkRating();
  await Future<void>.delayed(const Duration(seconds: 2));
  if (context.mounted) showRatingIfDue(context);
}

/// Về màn chính: tới lúc thì hiện hộp đánh giá (mỗi lần tới lúc chỉ hiện 1 lần).
void showRatingIfDue(BuildContext context) {
  if (!_due || _showing || !loggedIn()) return;
  // màn khác (camera, hồ sơ...) đang nằm trên: để lần về màn chính sau
  if (ModalRoute.of(context)?.isCurrent == false) return;
  _due = false;
  _showing = true;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _RatingSheet(),
  ).whenComplete(() => _showing = false);
}

class _RatingSheet extends StatefulWidget {
  const _RatingSheet();
  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int stars = 0;
  final note = TextEditingController();
  bool busy = false, answered = false;

  static const _labels = ['', 'Rất tệ', 'Chưa tốt', 'Tạm được', 'Tốt', 'Rất tốt'];

  @override
  void dispose() {
    // vuốt đóng / bấm ra ngoài mà chưa trả lời: coi như "Để sau"
    if (!answered) _send(later: true).catchError((_) => <String, dynamic>{});
    note.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _send({bool later = false}) async {
    answered = true;
    var version = '';
    try {
      final p = await PackageInfo.fromPlatform();
      version = '${p.version}+${p.buildNumber}';
    } catch (_) {}
    return post('/feedback', {
      'later': later,
      if (!later) 'stars': stars,
      if (!later) 'comment': note.text.trim(),
      'version': version,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    });
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      final j = await _send();
      if (mounted) Navigator.pop(context);
      toast(msgsOf(j));
    } catch (e) {
      answered = false;
      if (mounted) setState(() => busy = false);
      toast(errMsg(e));
    }
  }

  Future<void> later() async {
    try {
      await _send(later: true);
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Bạn thấy app Vua Thầu thế nào?', style: T.secT, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text('Bạn đã chụp hơn 30 ảnh. Chấm điểm giúp Vua Thầu làm app tốt hơn nhé.', style: T.muted, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var s = 1; s <= 5; s++)
                IconButton(
                  iconSize: 40,
                  tooltip: '$s sao',
                  onPressed: busy ? null : () => setState(() => stars = s),
                  icon: Icon(s <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: s <= stars ? const Color(0xFFF5B301) : C.muted),
                ),
            ],
          ),
          SizedBox(height: 20, child: Text(_labels[stars], style: T.label, textAlign: TextAlign.center)),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            enabled: !busy,
            decoration: InputDecoration(
              hintText: stars > 0 && stars <= 3 ? 'Điều gì làm bạn chưa hài lòng? (không bắt buộc)' : 'Góp ý thêm (không bắt buộc)',
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 10,
            children: [
              Expanded(child: Btn('Để sau', disabled: busy, onPressed: later)),
              Expanded(child: Btn('Gửi đánh giá', kind: BtnKind.primary, busy: busy, disabled: stars == 0, onPressed: submit)),
            ],
          ),
        ],
      ),
    ),
  );
}
