// Bản web (iPhone dùng PWA): không có ML Kit, không xin cảm biến (iOS hỏi quyền chuyển động). Trợ lý khung ngắm tắt.
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'scan_text.dart';

ImageFormatGroup liveImageFormat() => ImageFormatGroup.jpeg;

class Live extends ChangeNotifier {
  bool get scans => false;
  String phone = '', company = '';
  TextPiece? phoneBox, companyBox;
  bool anyText = false;
  double? light;
  double roll = 0;
  bool shaky = false, down = false;

  Future<void> start(CameraController c) async {}
  Future<void> stopStream() async {}
  set paused(bool p) {}
}
