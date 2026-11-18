// Nộp hồ sơ mới (POST /houses): chụp bằng camera Vua Thầu, hoặc chọn ảnh có sẵn.
import 'package:flutter/material.dart';

import '../api.dart';
import '../page.dart';
import '../picker.dart';
import '../ui.dart';
import 'home_shell.dart' show TopActions;
import 'camera.dart';
import 'house.dart';

class SubmitScreen extends StatefulWidget {
  const SubmitScreen({super.key});
  @override
  State<SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<SubmitScreen> implements Reloadable {
  @override
  Future<void> load() async {} // màn tĩnh, không cần tải

  @override
  Widget build(BuildContext context) {
    final min = cfg.minPhotos;
    return Column(children: [
      const VtAppBar(title: 'Nộp hồ sơ mới', sub: 'Chụp ngay hoặc chọn ảnh có sẵn', right: TopActions()),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          // Cách khuyên dùng: khung navy chuyển màu + 1 nút chính
          Container(
            decoration: BoxDecoration(gradient: navyGradient, borderRadius: BorderRadius.circular(R.card), boxShadow: cardShadow),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              const Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                Ic('camera', color: C.amber, size: 22),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                    Text('Camera Vua Thầu', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                    Text('Tự in giờ, ngày, địa chỉ và toạ độ GPS lên ảnh như Timemark. Ảnh chụp ở đây luôn đủ điều kiện về giờ và vị trí.',
                        style: TextStyle(color: C.heroMuted, fontSize: 13, height: 1.4)),
                  ]),
                ),
              ]),
              Btn('Chụp ảnh công trình', icon: 'camera', kind: BtnKind.primary, onPressed: () => push(context, const CameraScreen())),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(spacing: 10, children: [
              const Expanded(child: Divider()),
              Text('HOẶC', style: T.formHead.copyWith(color: C.subtle)),
              const Expanded(child: Divider()),
            ]),
          ),
          PhotoPicker(
            path: '/houses',
            have: 0,
            valid: 0,
            title: 'Chọn ảnh có sẵn trong máy',
            onUploaded: (j) {
              final id = houseIdOf(j);
              if (id != null) push(context, HouseScreen(id: id));
            },
          ),
          const Padding(padding: EdgeInsets.only(top: 12, bottom: 8), child: Sec('Ảnh thế nào thì đạt')),
          Box(gap: 14, children: [
            const _Tip(n: '1', title: 'Có giờ chụp và vị trí', text: 'Camera Vua Thầu tự in lên ảnh. Ảnh chọn sẵn phải chụp bằng Timemark trong 30 ngày.'),
            const _Tip(n: '2', title: 'Thấy rõ công trình đang xây', text: 'Không chụp lại màn hình, không dùng ảnh đã nộp.'),
            const _Tip(n: '3', title: 'Chụp bảng hiệu nhà thầu', text: 'AI đọc tên và SĐT nhà thầu, tự điền giúp bạn.'),
            _Tip(
              icon: 'wallet',
              title: '$min ảnh đạt: ${money(cfg.payFor(min))} · từ ${min + 1} ảnh: ${money(cfg.payFor(min + 1))}',
              text: 'Được trả gộp khi bạn có đủ ${cfg.payMin} hồ sơ đã duyệt.',
            ),
          ]),
        ]),
      ),
    ]);
  }
}

/// Kết quả POST /houses: {house_id: 123} -> 123; house_id null (không ảnh nào được nhận) -> null
int? houseIdOf(Json j) {
  final v = j['house_id'];
  final id = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  return id != null && id > 0 ? id : null;
}

class _Tip extends StatelessWidget {
  const _Tip({this.n, this.icon, required this.title, required this.text});
  final String? n, icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: C.soft, borderRadius: BorderRadius.circular(R.ctl), border: Border.all(color: C.line)),
          alignment: Alignment.center,
          child: icon != null ? Ic(icon!, size: 14, color: C.navy3) : Text('0${n!}', style: T.mono.copyWith(color: C.navy, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: T.bold),
            Text(text, style: T.muted),
          ]),
        ),
      ]);
}
