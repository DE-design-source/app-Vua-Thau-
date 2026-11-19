// Trợ lý khung ngắm (app Android): đọc chữ trên khung hình bằng ML Kit ngay trên máy (không cần mạng, không tốn tiền),
// tìm SĐT + tên nhà thầu trên bảng hiệu; đo độ sáng khung hình; cảm biến: máy nghiêng, rung tay, chĩa xuống đất.
// Quét ~2 lần/giây, bỏ qua khung hình khi đang bận để máy yếu không giật.
import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'scan_text.dart';

/// Định dạng khung hình xin camera: NV21 để ML Kit đọc thẳng (Android); nơi khác giữ JPEG như cũ.
ImageFormatGroup liveImageFormat() => defaultTargetPlatform == TargetPlatform.android ? ImageFormatGroup.nv21 : ImageFormatGroup.jpeg;

class Live extends ChangeNotifier {
  /// Có quét chữ trực tiếp (chỉ app Android).
  bool get scans => defaultTargetPlatform == TargetPlatform.android;

  String phone = '', company = '';
  TextPiece? phoneBox, companyBox;
  bool anyText = false;
  double? light; // độ sáng trung bình 0..255
  double roll = 0; // độ nghiêng trái / phải (độ)
  bool shaky = false, down = false;

  final _phone = Steady(), _company = Steady();
  TextRecognizer? _rec;
  CameraController? _cam;
  bool _busy = false, _paused = false, _dead = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0), _notified = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<AccelerometerEvent>? _acc;
  final _mags = <double>[];

  Future<void> start(CameraController c) async {
    _cam = c;
    _acc ??= accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(_onAcc, onError: (_) {});
    if (!scans) return;
    _rec ??= TextRecognizer(script: TextRecognitionScript.latin);
    try {
      if (!c.value.isStreamingImages) await c.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('live: không mở được luồng khung hình: $e');
    }
  }

  /// Camera bị đóng (ra màn hình chính): dừng luồng khung hình, giữ cảm biến.
  Future<void> stopStream() async {
    final c = _cam;
    _cam = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
  }

  /// Tạm ngừng đọc chữ (đang chụp, in chữ lên ảnh).
  set paused(bool p) => _paused = p;

  void _onAcc(AccelerometerEvent e) {
    // cầm dọc: trọng lực chủ yếu theo y; x lớn = nghiêng trái / phải; z lớn = màn hình ngửa lên (camera chĩa xuống đất)
    roll = math.atan2(e.x, e.y) * 180 / math.pi;
    down = e.z > 7.5;
    _mags.add(math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
    if (_mags.length > 12) _mags.removeAt(0);
    final mean = _mags.reduce((a, b) => a + b) / _mags.length;
    final sd = math.sqrt(_mags.map((m) => (m - mean) * (m - mean)).reduce((a, b) => a + b) / _mags.length);
    shaky = _mags.length >= 8 && sd > 0.9;
    _notify();
  }

  void _notify() {
    final now = DateTime.now();
    if (_dead || now.difference(_notified).inMilliseconds < 200) return;
    _notified = now;
    notifyListeners();
  }

  Future<void> _onFrame(CameraImage img) async {
    final now = DateTime.now();
    if (_busy || _paused || _dead || now.difference(_last).inMilliseconds < 450) return;
    _busy = true;
    _last = now;
    try {
      final y = img.planes.first.bytes;
      final n = math.min(y.length, img.width * img.height);
      var sum = 0, cnt = 0;
      for (var i = 0; i < n; i += 97) {
        sum += y[i];
        cnt++;
      }
      if (cnt > 0) light = sum / cnt;

      final rec = _rec, cam = _cam;
      if (rec == null || cam == null || img.planes.length != 1) return; // NV21: 1 lớp dữ liệu
      final rot = InputImageRotationValue.fromRawValue(cam.description.sensorOrientation) ?? InputImageRotation.rotation90deg;
      final turned = rot == InputImageRotation.rotation90deg || rot == InputImageRotation.rotation270deg;
      final w = (turned ? img.height : img.width).toDouble(), h = (turned ? img.width : img.height).toDouble();
      final input = InputImage.fromBytes(
        bytes: img.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rot,
          format: InputImageFormat.nv21,
          bytesPerRow: img.planes.first.bytesPerRow,
        ),
      );
      final r = await rec.processImage(input);
      TextPiece piece(String t, Rect b) => TextPiece(t, b.left / w, b.top / h, b.right / w, b.bottom / h);
      final blocks = [for (final b in r.blocks) piece(b.text, b.boundingBox)];
      final lines = [for (final b in r.blocks) for (final l in b.lines) piece(l.text, l.boundingBox)];
      final byBlock = findInPieces(blocks), byLine = findInPieces(lines);
      final t = DateTime.now();
      final ph = byLine.phone.isNotEmpty ? byLine.phone : byBlock.phone;
      phone = _phone.push(ph, t);
      company = _company.push(byBlock.company, t);
      if (ph.isNotEmpty) phoneBox = byLine.phone.isNotEmpty ? byLine.phoneBox : byBlock.phoneBox;
      if (byBlock.company.isNotEmpty) companyBox = byBlock.companyBox;
      if (phone.isEmpty) phoneBox = null;
      if (company.isEmpty) companyBox = null;
      anyText = byBlock.anyText;
      _notify();
    } on PlatformException catch (e) {
      debugPrint('live: ML Kit lỗi: ${e.message}');
    } catch (e) {
      debugPrint('live: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _dead = true;
    _acc?.cancel();
    stopStream();
    _rec?.close();
    super.dispose();
  }
}
