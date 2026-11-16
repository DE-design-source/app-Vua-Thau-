// Nộp hồ sơ mới (POST /houses): chụp bằng camera Vua Thầu, hoặc chọn ảnh có sẵn.
import 'package:flutter/material.dart';

import '../api.dart';
import '../page.dart';
import '../picker.dart';
import '../ui.dart';
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
      const VtAppBar(title: 'Nộp hồ sơ mới', sub: 'Chụp ngay hoặc chọn ảnh có sẵn'),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          Material(
            color: C.navy,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => push(context, const CameraScreen()),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(spacing: 14, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: const Ic('camera', color: C.navy, size: 26),
                  ),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text('Chụp bằng camera Vua Thầu', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                      Text('Tự in giờ, thứ, ngày tháng năm, địa chỉ GPS lên ảnh như Timemark', style: TextStyle(color: C.heroMuted, fontSize: 13)),
                    ]),
                  ),
                  const Ic('right', color: Colors.white),
                ]),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('hoặc', textAlign: TextAlign.center, style: T.muted)),
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
          const Padding(padding: EdgeInsets.only(top: 24, bottom: 12), child: Text('Ảnh thế nào thì đạt?', style: T.secT)),
          Box(children: [
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
          width: 28,
          height: 28,
          decoration: const BoxDecoration(color: C.amberBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: icon != null ? Ic(icon!, size: 16, color: C.warn) : Text(n!, style: const TextStyle(fontWeight: FontWeight.w800, color: C.warn)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: T.bold),
            Text(text, style: T.muted),
          ]),
        ),
      ]);
}
