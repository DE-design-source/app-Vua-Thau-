// Camera nghiệm thu kiểu Timemark (như /chup của web): khung ngắm + GPS + địa chỉ, in dải chữ Timemark lên ảnh.
// Chưa có GPS thì không cho chụp: ảnh nghiệm thu bắt buộc có vị trí.
// Trợ lý khung ngắm (app Android, lib/live): đọc chữ trên khung hình ngay trên máy, khoanh SĐT + tên nhà thầu trên
// bảng hiệu (bấm Dùng hoặc chụp trúng là lưu vào hồ sơ), nhắc tối / rung tay / nghiêng / chĩa xuống đất, nhắc chụp bảng hiệu.
// Chế độ VIDEO: quay ngay trong màn hình (tối đa 3 phút / video, 5 video / hồ sơ; bản web mở máy quay của điện thoại),
// video lưu tạm, tải lên cùng hồ sơ khi bấm Tải lên (hồ sơ có video được cộng thưởng).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../check.dart';
import '../lfile.dart';
import '../live/live.dart';
import '../picker.dart';
import '../stamp.dart';
import '../toast.dart';
import '../ui.dart';
import '../video.dart' show maxVideos, mb, videoLimit, videoMime;
import 'house.dart';
import 'nt_report.dart';
import 'report.dart';

class _Clip {
  _Clip(this.path, this.name, this.bytes, this.secs);
  final String path, name;
  final int bytes, secs;
}

const _maxClip = Duration(minutes: 3);

// Danh sách camera của máy: hỏi 1 lần, dùng lại (lần đầu CameraX khởi động ~0,3-1 giây).
Future<List<CameraDescription>>? _cams;
Future<List<CameraDescription>> _cameras() =>
    _cams ??= availableCameras().then(
      (v) {
        if (v.isEmpty) _cams = null;
        return v;
      },
      onError: (Object e) {
        _cams = null;
        throw e;
      },
    );

/// Gọi sớm (mở app) để bấm Chụp hình là camera lên ngay. Bản web bỏ qua (trình duyệt sẽ hỏi quyền camera).
void warmCamera() {
  if (!kIsWeb) _cameras().ignore();
}

/// Mở camera chụp hồ sơ mới.
void openCamera(BuildContext context) => push(context, const CameraScreen());

/// Kết quả POST /houses: {house_id: 123} -> 123; house_id null (không ảnh nào được nhận) -> null
int? houseIdOf(Json j) {
  final v = j['house_id'];
  final id = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  return id != null && id > 0 ? id : null;
}

// nhà thầu: hạng mục chọn nhanh ở màn Xác nhận nhật ký (thiết kế "Xác nhận & tải lên")
const _ntCats = ntCategories;
const _ntWeek = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật']; // DateTime.weekday: 1 = thứ Hai

class _Shot {
  _Shot(this.path, this.meta);
  final String path;
  final Map<String, Object> meta;
}

bool _far(Pos? a, Pos b) => a == null || math.sqrt(math.pow(a.lat - b.lat, 2) + math.pow((a.lng - b.lng) * math.cos(b.lat * math.pi / 180), 2)) * 111320 > 25;

class CameraScreen extends StatefulWidget {
  /// hid = 0: hồ sơ mới. have: số ảnh hồ sơ đã có.
  /// ntProject > 0: nhà thầu chụp nhật ký thi công cho dự án này (không AI kiểm ảnh, không tiền;
  /// Xong -> màn Xác nhận nhật ký: công trình + khớp GPS, hạng mục hôm nay, ghi chú -> tải lên). ntLat/ntLng: vị trí dự án nếu có.
  /// ntBrand: tên công ty nhà thầu in trên ảnh (dải chữ mới: tên công ty | ngày giờ, địa chỉ, GPS).
  /// ntLogo / ntScale / ntBadge: màn Logo trên ảnh (logo công ty thay tên chữ, cỡ, nhãn Vua Thầu xác minh).
  const CameraScreen({super.key, this.hid = 0, this.have = 0, this.ntProject = 0, this.ntName = '', this.ntLat, this.ntLng, this.ntBrand = '', this.ntLogo, this.ntScale = 1, this.ntBadge = false, this.ntPick});
  final int hid, have, ntProject;
  final String ntName, ntBrand;
  final ui.Image? ntLogo;
  final double ntScale;
  final bool ntBadge;

  /// ntPick: nhà thầu bấm Chụp hình -> vào camera ngay (chưa có dự án), chụp xong mới chọn dự án (góp ý 24/11/2026).
  /// Trả về dự án đã chọn ({id, name, lat, lng}) hoặc null.
  final Future<Map<String, dynamic>?> Function(BuildContext context)? ntPick;
  final double? ntLat, ntLng;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  // dự án của nhật ký (nhà thầu); chụp trước chọn sau: 0 cho tới khi chọn
  late int ntPid = widget.ntProject;
  late String ntPname = widget.ntName;
  late double? ntPlat = widget.ntLat, ntPlng = widget.ntLng;
  bool get _nt => widget.ntProject > 0 || widget.ntPick != null;

  /// Chọn / đổi dự án cho nhật ký (true: đã có dự án).
  Future<bool> _pickProject() async {
    final pick = widget.ntPick;
    if (pick == null) return ntPid > 0;
    final p = await pick(context);
    if (p == null || !mounted) return ntPid > 0;
    setState(() {
      ntPid = asInt(p['id']);
      ntPname = str(p['name']);
      ntPlat = p['lat'] is num ? (p['lat'] as num).toDouble() : null;
      ntPlng = p['lng'] is num ? (p['lng'] as num).toDouble() : null;
      err = '';
    });
    return ntPid > 0;
  }

  CameraController? cam;
  bool camReady = false, denied = false;
  Pos? pos;
  String gpsErr = '', addr = '';
  DateTime now = DateTime.now();
  final shots = <_Shot>[];
  bool busy = false, review = false, torch = false;
  int stamping = 0; // ảnh đã chụp, đang in giờ / vị trí (chạy nền)
  Future<void> _stamps = Future.value(); // chuỗi in chữ: lần lượt từng ảnh, giữ thứ tự
  bool flash = false; // chớp trắng lúc bấm chụp
  double zoom = 1, minZoom = 1, maxZoom = 1, _zoomFrom = 1; // phóng to / thu nhỏ (chụm 2 ngón hoặc nút 1x, 2x...)
  bool _zoomBusy = false;
  double? _zoomNext;
  final clips = <_Clip>[]; // video vừa quay, chưa tải lên
  final ntNote = TextEditingController(), ntNoteFocus = FocusNode(); // nhà thầu: ghi chú nhật ký
  final ntCats = <String>{}; // nhà thầu: hạng mục hôm nay
  bool videoMode = false, recording = false;
  DateTime? recAt;
  Timer? recTimer;
  int? doneHid; // ảnh đã lên hồ sơ này (video tải lỗi: thử lại chỉ tải video)
  String upWhat = '';
  double? pct;
  String err = '';
  final checks = Checks(); // AI kiểm từng ảnh ngay sau khi chụp
  final live = Live(); // trợ lý khung ngắm
  String ctName = '', ctPhone = ''; // nhà thầu quét từ bảng hiệu (CTV bấm Dùng / chụp trúng bảng hiệu)
  bool signShot = false; // đã có ảnh chụp trúng bảng hiệu
  Pos? looked;
  Timer? clock;
  StreamSubscription<Position>? gps;

  int get left => cfg.maxPhotos - widget.have;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checks.addListener(_tick);
    live.addListener(_tick);
    clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => now = DateTime.now()));
    _openCam();
    _startGps();
  }

  void _tick() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock?.cancel();
    gps?.cancel();
    recTimer?.cancel();
    live.removeListener(_tick);
    live.dispose();
    cam?.dispose();
    checks.removeListener(_tick);
    checks.dispose();
    ntNote.dispose();
    ntNoteFocus.dispose();
    super.dispose();
  }

  // Ra màn hình chính rồi quay lại: đóng / mở lại camera
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = cam;
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      if (c != null) {
        // đang quay thì lưu đoạn đã quay trước khi đóng camera
        final stop = recording ? _stopRec() : Future<void>.value();
        stop.whenComplete(() {
          cam = null;
          if (mounted) setState(() => camReady = false);
          live.stopStream().whenComplete(c.dispose);
        });
      }
    } else if (s == AppLifecycleState.resumed && cam == null) {
      _openCam();
      if (gps == null) _startGps();
    }
  }

  Future<void> _openCam() async {
    try {
      final all = await _cameras();
      if (all.isEmpty) throw CameraException('none', 'Máy không có camera');
      final back = all.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => all.first);
      // 1920x1080 (không lấy "max"): CameraX dùng CÙNG độ phân giải cho khung ngắm, ảnh chụp và luồng khung hình quét chữ.
      // "max" (12-50 MP) làm mỗi khung hình quét chữ nặng hàng chục MB -> mở camera chậm, khung ngắm giật, chụp lâu;
      // trong khi ảnh nộp lên vẫn bị thu về 1920px (stamp.dart). Video 6 Mbit/s: 3 phút ~ 135 MB, dưới giới hạn 200 MB.
      final c = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: liveImageFormat(), videoBitrate: 6000000);
      await c.initialize();
      // khoá dọc TRƯỚC khi hiện khung ngắm: chưa khoá thì khung ngắm xoay theo cảm biến (cầm nghiêng là nằm ngang).
      // Bản web: trình duyệt có thể không khoá xoay, bỏ qua
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        cam = c;
        camReady = true;
        denied = false;
        zoom = 1;
      });
      // giới hạn zoom của máy (bản web có thể không hỗ trợ: giữ 1x, ẩn nút zoom)
      try {
        final lo = await c.getMinZoomLevel(), hi = await c.getMaxZoomLevel();
        if (mounted && cam == c) {
          setState(() {
            minZoom = lo;
            maxZoom = math.min(hi, 10); // quá 10x ảnh vỡ, không dùng được cho nghiệm thu
            zoom = 1.0.clamp(minZoom, maxZoom);
          });
        }
      } catch (_) {}
      // đèn làm sau khi khung ngắm đã hiện (bản web có thể không có đèn, bỏ qua)
      try {
        await c.setFlashMode(torch ? FlashMode.torch : FlashMode.off);
      } catch (_) {}
      if (!mounted || cam != c) return;
      live.start(c);
    } on CameraException catch (e) {
      if (e.code.startsWith('CameraAccess')) {
        if (mounted) setState(() => denied = true);
      } else {
        toast('Không mở được camera: ${e.description ?? e.code}');
      }
    }
  }

  // GPS + địa chỉ (máy chủ hỏi OpenStreetMap / Google, như web)
  Future<void> _lookup(Pos p) async {
    try {
      final j = await api('/geocode?lat=${p.lat}&lng=${p.lng}');
      if (mounted) setState(() => addr = str(j['address']));
    } catch (_) {
      /* mất mạng: ảnh vẫn có toạ độ */
    }
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => gpsErr = 'Chưa bật Vị trí (GPS) của máy');
        // nghe khi người dùng bật lại
        Geolocator.getServiceStatusStream().firstWhere((s) => s == ServiceStatus.enabled).then((_) {
          if (mounted && gps == null) _startGps();
        });
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        setState(() => gpsErr = 'Chưa cho phép Vị trí');
        return;
      }
      // GPS bật nguội mất vài giây mới có toạ độ: dùng vị trí máy vừa biết (≤ 90 giây, sai số ≤ 50 m) để chụp được ngay,
      // luồng GPS bên dưới cập nhật lại liền sau đó.
      if (!kIsWeb && pos == null) {
        try {
          final l = await Geolocator.getLastKnownPosition();
          if (l != null && mounted && pos == null && l.accuracy <= 50 && DateTime.now().difference(l.timestamp).inSeconds.abs() <= 90) {
            final cur = Pos(l.latitude, l.longitude, l.accuracy);
            setState(() => pos = cur);
            looked = cur;
            _lookup(cur);
          }
        } catch (_) {}
      }
      gps = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 1, intervalDuration: const Duration(seconds: 2)),
      ).listen((l) {
        final cur = Pos(l.latitude, l.longitude, l.accuracy);
        setState(() {
          pos = cur;
          gpsErr = '';
        });
        if (_far(looked, cur)) {
          looked = cur;
          _lookup(cur);
        }
      }, onError: (_) => setState(() => gpsErr = 'Không bật được GPS, bật Vị trí trong cài đặt máy'));
    } catch (_) {
      setState(() => gpsErr = 'Không bật được GPS, bật Vị trí trong cài đặt máy');
    }
  }

  Future<void> leave() async {
    if (recording) await _stopRec();
    await _stamps;
    if (!mounted) return;
    if ((shots.isEmpty && clips.isEmpty) ||
        await confirm(context, title: 'Bỏ ảnh, video vừa chụp?', text: 'Ảnh, video chưa tải lên sẽ mất.', ok: 'Bỏ', cancel: 'Ở lại')) {
      for (final s in shots) {
        deleteLocal(s.path);
      }
      for (final v in clips) {
        deleteLocal(v.path);
      }
      shots.clear();
      clips.clear();
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ---------- quay video ----------
  bool get canRecord => camReady && !busy && clips.length < maxVideos;

  Future<void> toggleRec() => recording ? _stopRec() : _startRec();

  Future<void> _startRec() async {
    final c = cam;
    if (c == null || !canRecord) return;
    if (kIsWeb) {
      // bản web (iPhone): mở máy quay của điện thoại
      try {
        final x = await ImagePicker().pickVideo(source: ImageSource.camera, maxDuration: _maxClip);
        if (x != null) await _addClip(x.path, x.name, 0);
      } catch (e) {
        toast('Không mở được máy quay: $e');
      }
      return;
    }
    setState(() => busy = true);
    try {
      await live.stopStream(); // quay video không chạy kèm quét chữ (máy yếu không đủ sức)
      await c.startVideoRecording();
      recAt = DateTime.now();
      recTimer = Timer(_maxClip, _stopRec);
      HapticFeedback.mediumImpact();
      setState(() => recording = true);
    } catch (e) {
      toast('Không quay được video: $e');
      live.start(c);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _stopRec() async {
    recTimer?.cancel();
    recTimer = null;
    final c = cam;
    if (c == null || !recording) return;
    final secs = recAt == null ? 0 : DateTime.now().difference(recAt!).inSeconds;
    setState(() => recording = false);
    try {
      final x = await c.stopVideoRecording();
      HapticFeedback.mediumImpact();
      await _addClip(x.path, x.name, secs);
    } catch (e) {
      toast('Lưu video không được: $e');
    } finally {
      if (cam != null) live.start(cam!);
    }
  }

  Future<void> _addClip(String path, String name, int secs) async {
    final n = await localLength(path);
    if (n > videoLimit) {
      toast('Video quá 200 MB, quay ngắn lại.');
      deleteLocal(path);
      return;
    }
    final file = name.isNotEmpty && name.contains('.') ? name : 'video-${clips.length + 1}.mp4';
    if (!mounted) return;
    setState(() => clips.add(_Clip(path, file, n, secs)));
    toast('Đã quay video ${clips.length} (${mb(n)}). ${videoTip()}'.trim());
  }

  void dropClip(int k) {
    deleteLocal(clips[k].path);
    setState(() => clips.removeAt(k));
  }

  /// Đặt mức zoom. Chụm ngón gọi liên tục: chỉ gửi xuống camera 1 lệnh một lúc, lệnh mới nhất thắng.
  void setZoom(double z) {
    final v = z.clamp(minZoom, maxZoom).toDouble();
    if ((v - zoom).abs() < 0.01) return;
    setState(() => zoom = v);
    _zoomNext = v;
    if (_zoomBusy) return;
    _zoomBusy = true;
    () async {
      while (_zoomNext != null) {
        final t = _zoomNext!;
        _zoomNext = null;
        try {
          await cam?.setZoomLevel(t);
        } catch (_) {}
      }
      _zoomBusy = false;
    }();
  }

  /// vertical: cột dọc mép phải khung ngắm, mức lớn ở trên (thiết kế: 5, 2, 1x, .5).
  Widget _zoomBar({bool vertical = false}) {
    final stops = <double>[
      if (minZoom < 0.95) minZoom, // ống góc rộng (máy có): thấy rộng hơn
      1,
      for (final s in const [2.0, 5.0, 10.0])
        if (s <= maxZoom + 0.01) s,
    ];
    // nút đang chọn: mức gần nhất với zoom hiện tại
    var on = stops.first;
    for (final s in stops) {
      if ((s - zoom).abs() < (on - zoom).abs()) on = s;
    }
    String label(double s) {
      final v = s == on ? zoom : s; // nút đang chọn hiện đúng mức đang zoom (vd 1.6x)
      final t = v < 1 ? v.toStringAsFixed(1) : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
      return s == on ? '${t}x' : t.replaceFirst('0.', '.');
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .4), borderRadius: BorderRadius.circular(999)),
      child: Flex(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final s in vertical ? stops.reversed : stops)
            Semantics(
              button: true,
              label: 'Zoom ${s}x',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setZoom(s);
                },
                child: Container(
                  width: s == on || vertical ? 40 : 34,
                  height: s == on && vertical ? 40 : 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: s == on ? Colors.black.withValues(alpha: .55) : Colors.transparent, shape: BoxShape.circle),
                  child: Text(
                    label(s),
                    style: TextStyle(
                      color: s == on ? C.amber : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: s == on ? 12.5 : 11.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _clock(int s) => '${p2(s ~/ 60)}:${p2(s % 60)}';

  bool get canShoot => camReady && pos != null && !busy && shots.length + stamping < left;
  bool get hasMedia => shots.isNotEmpty || clips.isNotEmpty || stamping > 0;

  Future<void> shoot() async {
    final c = cam;
    if (!canShoot || c == null) return;
    final date = DateTime.now(), p = pos!, a = addr;
    // chụp trúng bảng hiệu: giữ SĐT / tên đang thấy cho ảnh này
    final seenPhone = live.phone, seenName = live.company;
    setState(() {
      busy = true;
      flash = true;
    });
    live.paused = true;
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => flash = false);
    });
    final XFile raw;
    try {
      raw = await c.takePicture();
    } catch (e) {
      toast('Chụp không được: $e');
      live.paused = stamping > 0;
      if (mounted) setState(() => busy = false);
      return;
    }
    // máy chụp xong là bấm chụp tiếp được; in giờ / vị trí lên ảnh chạy nền
    if (mounted) {
      setState(() {
        busy = false;
        stamping++;
      });
    }
    _stamps = _stamps.then((_) => _stamp(raw.path, date, p, a, seenName, seenPhone));
  }

  Future<void> _stamp(String rawPath, DateTime date, Pos p, String a, String seenName, String seenPhone) async {
    try {
      final path = await stampPhoto(rawPath, StampData(date, p, a, brand: widget.ntBrand, logo: widget.ntLogo, scale: widget.ntScale, badge: widget.ntBadge));
      if (!mounted) {
        deleteLocal(path);
        return;
      }
      final meta = <String, Object>{
        't': '${date.year}-${p2(date.month)}-${p2(date.day)} ${p2(date.hour)}:${p2(date.minute)}',
        'lat': p.lat,
        'lng': p.lng,
        'acc': p.acc.round(),
        'addr': a,
        if (seenName.isNotEmpty) 'ct_name': seenName,
        if (seenPhone.isNotEmpty) 'ct_phone': seenPhone,
      };
      final firstSign = (seenPhone.isNotEmpty || seenName.isNotEmpty) && ctName.isEmpty && ctPhone.isEmpty;
      setState(() {
        shots.add(_Shot(path, meta));
        if (seenPhone.isNotEmpty || seenName.isNotEmpty) signShot = true;
        if (ctName.isEmpty && seenName.isNotEmpty) ctName = seenName;
        if (ctPhone.isEmpty && seenPhone.isNotEmpty) ctPhone = seenPhone;
      });
      if (firstSign)
        toast('Đã lưu nhà thầu từ bảng hiệu: ${[if (seenName.isNotEmpty) seenName, if (seenPhone.isNotEmpty) prettyPhone(seenPhone)].join(' · ')}');
      if (!_nt) checks.run(path, meta: meta); // nhật ký nhà thầu: không AI kiểm ảnh
    } catch (e) {
      toast('In giờ, vị trí lên ảnh không được: $e');
    } finally {
      if (mounted) setState(() => stamping--);
      live.paused = stamping > 0 || busy;
    }
  }

  /// Mở màn xem lại: chờ các ảnh đang in chữ xong.
  Future<void> _openReview() async {
    await _stamps;
    if (mounted && (shots.isNotEmpty || clips.isNotEmpty)) setState(() => review = true);
  }

  void drop(int k) {
    deleteLocal(shots[k].path);
    setState(() {
      shots.removeAt(k);
      if (shots.isEmpty) review = false;
    });
  }

  /// Nhà thầu: tải 1 lần nhật ký (mô tả + ảnh + video) lên dự án.
  Future<void> _sendNt() async {
    if (shots.isEmpty && clips.isEmpty) {
      setState(() => err = 'Chụp ít nhất 1 ảnh hoặc quay 1 video cho nhật ký hôm nay.');
      return;
    }
    if (ntPid == 0 && !await _pickProject()) {
      if (mounted) setState(() => err = 'Chọn dự án cho nhật ký này rồi bấm Tải lên.');
      return;
    }
    // mô tả nhật ký = hạng mục đã chọn + ghi chú, vd "Cốp pha, Cốt thép. Lắp cốp pha cột tầng 2"
    final note = [if (ntCats.isNotEmpty) [for (final c in _ntCats) if (ntCats.contains(c)) c].join(', '), ntNote.text.trim()]
        .where((s) => s.isNotEmpty)
        .join('. ');
    if (!mounted) return;
    final meta = shots.isNotEmpty ? shots.first.meta : const <String, Object>{};
    setState(() {
      err = '';
      pct = 0;
      upWhat = 'Đang tải nhật ký…';
    });
    try {
      final j = await upload(
        '/nt/projects/$ntPid/logs',
        [
          for (var k = 0; k < shots.length; k++) UpFile('files', shots[k].path, 'nhat-ky-${k + 1}.jpg'),
          for (final v in clips) UpFile('files', v.path, v.name, videoMime(v.name)),
        ],
        fields: {'note': note, 'meta': jsonEncode({'t': meta['t'] ?? '', 'lat': meta['lat'], 'lng': meta['lng'], 'addr': meta['addr'] ?? ''})},
        onProgress: (p) {
          if (mounted) setState(() => pct = p);
        },
      );
      final skipped = ((j['skipped'] as List?) ?? const []).map((e) => '$e').toList();
      if (skipped.isNotEmpty) toast('Bỏ qua: ${skipped.join('; ')}');
      for (final s in shots) {
        deleteLocal(s.path);
      }
      for (final v in clips) {
        deleteLocal(v.path);
      }
      shots.clear();
      clips.clear();
      final logId = asInt((j['log'] as Map?)?['id']);
      if (!mounted) return;
      if (logId > 0) {
        // bước cuối (thiết kế): báo cáo gửi chủ nhà; đóng báo cáo = xong (màn gọi camera tải lại)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => NtReportScreen(projectId: ntPid, logId: logId, uploaded: asInt(j['photos']))),
          result: true,
        );
      } else {
        toast('${j['message'] ?? 'Đã lưu nhật ký.'}');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => err = '${errMsg(e)} Ảnh, video vẫn còn đây, bấm Tải lên để thử lại.');
    } finally {
      if (mounted) {
        setState(() {
          pct = null;
          upWhat = '';
        });
      }
    }
  }

  Future<void> send() async {
    if (recording) await _stopRec();
    await _stamps;
    if (_nt) return _sendNt();
    final target = widget.hid > 0 ? widget.hid : doneHid;
    if (shots.isEmpty && target == null) {
      setState(() => err = 'Chụp ít nhất 1 ảnh để tạo hồ sơ, rồi mới tải video lên.');
      return;
    }
    setState(() {
      err = '';
      pct = 0;
      upWhat = '';
    });
    try {
      int? id = target;
      if (shots.isNotEmpty) {
        id = await _sendPhotos();
        if (id == null) return;
        doneHid = id;
      }
      // video: từng cái một (file lớn), lỗi thì giữ lại để thử lại
      for (var k = 0; clips.isNotEmpty; k++) {
        final v = clips.first;
        setState(() {
          upWhat = 'Đang tải video ${k + 1}…';
          pct = 0;
        });
        final j = await upload(
          '/houses/$id/videos',
          [UpFile('files', v.path, v.name, videoMime(v.name))],
          onProgress: (p) {
            if (mounted) setState(() => pct = p);
          },
        );
        if (msgsOf(j).isNotEmpty) toast(msgsOf(j));
        deleteLocal(v.path);
        setState(() => clips.removeAt(0));
      }
      if (!mounted) return;
      final hid = id;
      if (hid != null && doneHid != null) {
        // có ảnh lên hồ sơ: bước cuối là gửi cập nhật cho chủ nhà qua Zalo (bỏ qua được);
        // hồ sơ mới thì đóng xong sang Chi tiết hồ sơ, hồ sơ có sẵn thì về Chi tiết hồ sơ đang mở
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReportScreen(id: hid, uploaded: true, openHouse: widget.hid == 0)));
      } else if (widget.hid > 0 || hid == null) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HouseScreen(id: hid)));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              err =
                  doneHid != null && shots.isEmpty
                      ? '${errMsg(e)} Ảnh đã lên hồ sơ; video vẫn còn đây, bấm Tải lên để thử lại.'
                      : '${errMsg(e)} Ảnh vẫn còn đây.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          pct = null;
          upWhat = '';
        });
      }
    }
  }

  /// Tải ảnh lên (hồ sơ mới / hồ sơ có sẵn). Trả mã hồ sơ, null khi không ảnh nào được nhận.
  Future<int?> _sendPhotos() async {
    {
      final j = await upload(
        widget.hid > 0 ? '/houses/${widget.hid}/photos' : '/houses',
        [for (var k = 0; k < shots.length; k++) UpFile('files', shots[k].path, 'vuathau-${k + 1}.jpg')],
        // nhà thầu CTV đã chọn từ bảng hiệu: gửi kèm ảnh đầu (máy chủ điền khi hồ sơ chưa có)
        fields: {
          'meta': jsonEncode([
            for (var k = 0; k < shots.length; k++)
              {...shots[k].meta, if (k == 0 && ctName.isNotEmpty) 'ct_name': ctName, if (k == 0 && ctPhone.isNotEmpty) 'ct_phone': ctPhone},
          ]),
        },
        onProgress: (p) {
          if (mounted) setState(() => pct = p);
        },
      );
      toast(msgsOf(j));
      final id = widget.hid > 0 ? widget.hid : houseIdOf(j);
      // hồ sơ mới: house_id null; hồ sơ có sẵn: added = 0
      if (widget.hid > 0 ? j.containsKey('added') && asInt(j['added']) == 0 : id == null) {
        setState(() => err = 'Không ảnh nào được nhận, xem lý do ở trên.');
        return null;
      }
      shots.clear();
      return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: !hasMedia && pct == null && !recording,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (review) {
            if (pct == null) setState(() => review = false);
          } else {
            leave();
          }
        },
        child: Scaffold(backgroundColor: Colors.black, body: denied ? _denied() : Stack(children: [_camera(), if (review) _review()])),
      ),
    );
  }

  Widget _denied() => Container(
    decoration: const BoxDecoration(gradient: navyGradient),
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Ic('camera', color: C.amber, size: 34),
                ),
              ),
              const Text(
                'Chưa cho phép Camera',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3),
              ),
              const Text(
                'Cho app dùng camera để chụp ảnh nghiệm thu: vào Cài đặt của máy, mục Ứng dụng, Vua Thầu, Quyền, bật Camera.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.heroMuted, height: 1.45),
              ),
              const SizedBox(height: 6),
              Btn('Mở cài đặt để cho phép', kind: BtnKind.primary, onPressed: () => Geolocator.openAppSettings()),
              Btn('Thử lại', onPressed: _openCam),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Quay lại',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _camera() {
    final n = widget.have + shots.length + stamping, min = cfg.minPhotos;
    final last = shots.isNotEmpty ? checks[shots.last.path] : null;
    final p = pos;
    final hint =
        p == null
            ? (gpsErr.isNotEmpty
                ? 'Ảnh nghiệm thu bắt buộc có vị trí. Bật quyền Vị trí cho app trong cài đặt máy.'
                : 'Đang chờ GPS để chụp. Ảnh nghiệm thu bắt buộc có vị trí.')
            : _nt
            ? (shots.isEmpty && clips.isEmpty
                ? (ntPname.isNotEmpty ? 'Nhật ký $ntPname: chụp ảnh / quay video việc làm hôm nay.' : 'Chụp ảnh / quay video việc làm hôm nay, chọn dự án sau.')
                : 'Bấm Xong để xác nhận nhật ký rồi tải lên.')
            : shots.length + stamping >= left
            ? 'Đã đủ số ảnh tối đa của hồ sơ. Bấm Xong để tải lên.'
            : n < min
            ? 'Chụp thêm ${min - n} ảnh nữa để đủ $min ảnh.'
            : n == min
            ? 'Đủ $min ảnh (${money(cfg.payFor(min))}). Chụp thêm 1 ảnh để được ${money(cfg.payFor(min + 1))}. ${videoTip()}'.trim()
            : 'Đủ ảnh (${money(cfg.payFor(min + 1))}). Bấm Xong để tải lên. ${videoTip()}'.trim();
    final (gpsCol, gpsText) =
        p == null
            ? (const Color(0xFFFF7A66), gpsErr.isNotEmpty ? gpsErr : 'Đang tìm GPS…')
            : p.acc <= 30
            ? (const Color(0xFF32D583), 'GPS ±${p.acc.round()}m')
            : p.acc <= 100
            ? (C.amber, 'GPS ±${p.acc.round()}m')
            : (const Color(0xFFFF7A66), 'GPS yếu ±${p.acc.round()}m, ra chỗ thoáng');
    final goal = min + 1; // đủ ảnh để được mức tiền cao nhất
    final nt = _nt;
    // viên tròn mờ trên nền ảnh
    BoxDecoration glass([Color? border]) => BoxDecoration(
      color: Colors.black.withValues(alpha: .38),
      borderRadius: BorderRadius.circular(999),
      border: border != null ? Border.all(color: border.withValues(alpha: .7)) : null,
    );
    Widget pill(String text, {Color bg = const Color(0x99000000), Color fg = Colors.white, Widget? lead}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (lead != null) lead,
          Flexible(
            child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
          ),
        ],
      ),
    );

    // ---- thanh trên (đè lên khung ngắm): đóng, đèn | GPS | số ảnh ----
    final topBar = Row(
      spacing: 8,
      children: [
        _round(onTap: leave, label: 'Đóng camera', child: const Ic('x', color: Colors.white, size: 22)),
        _round(
          onTap: () async {
            setState(() => torch = !torch);
            try {
              await cam?.setFlashMode(torch ? FlashMode.torch : FlashMode.off);
            } catch (_) {}
          },
          label: 'Đèn',
          on: torch,
          child: Ic('bolt', color: torch ? C.amberInk : Colors.white, size: 20),
        ),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: gpsErr.isNotEmpty ? () => Geolocator.openLocationSettings() : null,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: glass(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 7,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: gpsCol, shape: BoxShape.circle)),
                    Flexible(
                      child: Text(
                        gpsText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: nt ? glass() : BoxDecoration(color: n >= min ? const Color(0xFF16A34A) : Colors.black.withValues(alpha: .38), borderRadius: BorderRadius.circular(999)),
          alignment: Alignment.center,
          child: Text(
            nt ? '${shots.length + stamping} ảnh' : '$n/$min ảnh${n >= min ? ' ✓' : ''}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );

    // ---- dưới khung ngắm (màn ngang: cột bên phải): ảnh vừa chụp | nút chụp | Xong, rồi Ảnh / Video ----
    Widget shutterBar(bool v) => Flex(
      direction: v ? Axis.vertical : Axis.horizontal,
      children: [
        Expanded(
          child: Align(
            alignment: v ? Alignment.bottomCenter : Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: 'Xem ảnh vừa chụp',
              child: GestureDetector(
                onTap: hasMedia ? _openReview : null,
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(R.card),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            shots.isNotEmpty
                                ? localImage(shots.last.path, fit: BoxFit.cover, cacheWidth: 200)
                                : Center(child: Ic(clips.isNotEmpty ? 'video' : 'image', color: Colors.white54, size: 22)),
                            // ảnh vừa chụp đang in giờ / vị trí (chạy nền, vẫn chụp tiếp được)
                            if (stamping > 0)
                              const ColoredBox(
                                color: Color(0x66000000),
                                child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
                              ),
                          ],
                        ),
                      ),
                      if (hasMedia)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.black, width: 1.5)),
                            alignment: Alignment.center,
                            child: Text(
                              '${shots.length + stamping + clips.length}',
                              style: const TextStyle(color: C.amberInk, fontWeight: FontWeight.w700, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (videoMode)
          Semantics(
            button: true,
            label: recording ? 'Dừng quay' : 'Quay video',
            child: GestureDetector(
              onTap: recording || canRecord ? toggleRec : null,
              child: Opacity(
                opacity: recording || canRecord ? 1 : 0.4,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                  alignment: Alignment.center,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: recording ? 30 : 60,
                    height: recording ? 30 : 60,
                    decoration: BoxDecoration(color: const Color(0xFFE5322D), borderRadius: BorderRadius.circular(recording ? 8 : 30)),
                  ),
                ),
              ),
            ),
          )
        else
          Semantics(
            button: true,
            label: 'Chụp ảnh',
            child: GestureDetector(
              onTap: canShoot ? shoot : null,
              child: Opacity(
                opacity: canShoot ? 1 : 0.4,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                  alignment: Alignment.center,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(color: C.amber, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Ic('camera', color: C.amberInk, size: 26),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: Align(
            alignment: v ? Alignment.topCenter : Alignment.centerRight,
            child: Opacity(
              opacity: !hasMedia || recording ? 0.4 : 1,
              child: Material(
                color: Colors.transparent,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: const ShapeDecoration(gradient: blueGradient, shape: StadiumBorder()),
                  child: InkWell(
                    onTap: !hasMedia || recording ? null : _openReview,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          hasMedia ? 'Xong · ${shots.length + stamping + clips.length}' : 'Xong',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    final modeRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 18,
      children: [
        for (final (v, label) in [(false, 'Ảnh'), (true, 'Video')])
          GestureDetector(
            onTap: recording || busy ? null : () => setState(() => videoMode = v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Text(
                  label,
                  style: TextStyle(color: videoMode == v ? C.amber : Colors.white70, fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: .3),
                ),
                Container(width: 5, height: 5, decoration: BoxDecoration(color: videoMode == v ? C.amber : Colors.transparent, shape: BoxShape.circle)),
              ],
            ),
          ),
      ],
    );

    // thông báo trên khung ngắm, ưu tiên: kết quả AI ảnh vừa chụp > gợi ý cầm máy > hướng dẫn
    final coach = _coach();
    // góp ý 24/11: bỏ dòng hướng dẫn chung trên khung ngắm (che ảnh); chỉ còn cảnh báo thiếu GPS và hết chỗ video
    final tip = videoMode
        ? (clips.length >= maxVideos ? 'Đã đủ $maxVideos video. Bấm Xong để tải lên.' : '')
        : (p == null ? hint : '');

    return LayoutBuilder(
      builder: (context, box) {
        // Khung ngắm cùng tỷ lệ với ảnh (camera 1080p = 16:9, cầm dọc thành 9:16), RỘNG HẾT MÀN HÌNH, sát mép trên
        // (thanh trên đè lên ảnh): thấy gì chụp nấy, dải chữ trên khung ngắm nằm đúng chỗ như trên ảnh.
        // Màn thấp quá thì thu nhỏ vừa đủ chừa chỗ cho hàng nút chụp.
        final safe = MediaQuery.paddingOf(context);
        final c = cam;
        final raw = c != null && camReady && c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
        final ar = raw >= 1 ? raw : 1 / raw; // dài / ngắn
        // Màn NGANG (trình duyệt cầm ngang; app Android khoá dọc): khung ngắm ngang cao hết màn bên trái,
        // nút chụp thành cột bên phải. Ảnh chụp trên web cầm ngang cũng ra ngang, nên vẫn thấy gì chụp nấy.
        final land = box.maxWidth > box.maxHeight;
        const ctlH = 138.0, ctlW = 128.0; // hàng nút chụp + Ảnh / Video (dọc) / cột nút (ngang)
        final double fw, fh;
        if (land) {
          final h = math.min(box.maxHeight, (box.maxWidth - ctlW - safe.right) / ar);
          (fw, fh) = (h * ar, h);
        } else {
          // màn dọc: tràn viền (góp ý 24/11), khung ngắm phủ hết bề ngang + phần trên hàng nút; ảnh xem trước cắt bớt
          // mép (cover) cho kín khung, không chừa dải đen 2 bên
          (fw, fh) = (box.maxWidth, math.max(0.0, box.maxHeight - ctlH - safe.bottom));
        }
        final fl = land ? math.max(0.0, (box.maxWidth - ctlW - safe.right - fw) / 2) : 0.0;
        // khung xem trước đúng tỷ lệ camera theo chiều đang cầm; FittedBox cover phóng cho kín khung, cắt phần thừa
        final previewH = land ? fw / ar : fw * ar;
        final finder = SizedBox(
          width: fw,
          height: fh,
          // chụm 2 ngón để phóng to / thu nhỏ (cả lúc quay video)
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => _zoomFrom = zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount >= 2) setZoom(_zoomFrom * d.scale);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (c != null && camReady)
                  FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: fw, height: previewH, child: CameraPreview(c)))
                else
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                IgnorePointer(child: CustomPaint(painter: StampPainter(StampData(now, pos, addr, brand: widget.ntBrand, logo: widget.ntLogo, scale: widget.ntScale, badge: widget.ntBadge)))),
                IgnorePointer(child: CustomPaint(painter: _LivePainter(live.phoneBox, live.companyBox, live.roll))),
                if (recording && recAt != null)
                  Positioned(
                    right: 10,
                    bottom: fh * 0.24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFFE5322D), shape: BoxShape.circle)),
                          Text(
                            '${_clock(now.difference(recAt!).inSeconds.clamp(0, 9999))} / ${_clock(_maxClip.inSeconds)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                  ),
                // nút zoom nhanh dọc mép phải (5, 2, 1x, .5 như thiết kế)
                if (camReady && maxZoom > minZoom) Positioned(right: 10, top: fh * 0.36, child: _zoomBar(vertical: true)),
                // tiến độ đủ ảnh ở mép dưới khung (hồ sơ CTV)
                if (!nt) Positioned(left: 14, right: 14, bottom: 8, child: Segs(n: n, total: goal, dark: true)),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: flash ? 0.55 : 0,
                    duration: Duration(milliseconds: flash ? 0 : 160),
                    child: const ColoredBox(color: Colors.white, child: SizedBox.expand()),
                  ),
                ),
              ],
            ),
          ),
        );
        return Stack(
          children: [
            Positioned(left: fl, top: 0, width: fw, height: fh, child: finder),
            // mờ dần ở mép trên cho chữ trắng của thanh trên dễ đọc
            Positioned(
              left: fl,
              top: 0,
              width: fw,
              height: safe.top + 110,
              child: const IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x80000000), Color(0x00000000)]))),
              ),
            ),
            Positioned(left: fl + 12, width: fw - 24, top: safe.top + 8, child: topBar),
            Positioned(
              left: fl + 14,
              width: math.max(0.0, fw - 74),
              top: safe.top + 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 8,
                children: [
                  _liveTop(),
                  if (last != null)
                    Semantics(
                      liveRegion: true,
                      child: pill(
                        'Ảnh ${shots.length} · ${last.text}',
                        bg: switch (last.state) {
                          CheckState.ok => C.okBg,
                          CheckState.bad => C.badBg,
                          _ => const Color(0x99000000),
                        },
                        fg: switch (last.state) {
                          CheckState.ok => C.ok,
                          CheckState.bad => C.bad,
                          _ => Colors.white,
                        },
                        lead: last.state == CheckState.ok || last.state == CheckState.bad
                            ? null
                            : const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      ),
                    ),
                  if (coach != null)
                    Semantics(liveRegion: true, child: pill(coach, bg: C.amber, fg: C.amberInk))
                  else if (tip.isNotEmpty)
                    pill(tip),
                ],
              ),
            ),
            if (land)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: ctlW + safe.right,
                child: ColoredBox(
                  color: Colors.black,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(8, 12 + safe.top, 8 + safe.right, 12 + safe.bottom),
                    child: Column(spacing: 10, children: [Expanded(child: shutterBar(true)), modeRow]),
                  ),
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                top: fh,
                bottom: 0,
                child: ColoredBox(
                  color: Colors.black,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 6 + safe.bottom),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [shutterBar(false), modeRow]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 1 câu gợi ý cách chụp (ưu tiên lỗi làm hỏng ảnh trước). Không có gì cần nhắc: null.
  String? _coach() {
    if (!camReady || busy) return null;
    final l = live.light;
    if (l != null && l < 45) return torch ? 'Vẫn tối, ra chỗ sáng hơn' : 'Tối quá: bật đèn (nút tia sét) hoặc ra chỗ sáng';
    if (live.shaky) return 'Giữ yên tay để ảnh không bị nhoè';
    if (live.down) return 'Đưa máy lên, ngắm vào công trình';
    final r = live.roll.abs();
    if (r > 8 && r < 60) return 'Máy đang nghiêng ${r.round()}°, cầm thẳng theo vạch vàng';
    if (live.phone.isNotEmpty || live.company.isNotEmpty) return 'Thấy bảng hiệu: bấm chụp để lưu cả SĐT nhà thầu';
    if (live.scans && !signShot && shots.length >= 2) return 'Nhớ chụp 1 ảnh rõ bảng hiệu nhà thầu (tên + SĐT)';
    return null;
  }

  /// Thẻ "Bảng hiệu" trên khung ngắm: tên + SĐT đang thấy, bấm Dùng để lưu vào hồ sơ.
  Widget _liveTop() {
    final ph = live.phone, name = live.company;
    if (ph.isEmpty && name.isEmpty) return const SizedBox.shrink();
    final same = ph == ctPhone && (name.isEmpty || name == ctName);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(R.card)),
      child: Row(
        spacing: 8,
        children: [
          const Ic('spark', color: C.amber, size: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Bảng hiệu', style: TextStyle(color: C.amber, fontSize: 10.5, fontWeight: FontWeight.w700)),
                if (name.isNotEmpty)
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.25),
                  ),
                if (ph.isNotEmpty)
                  Text(
                    prettyPhone(ph),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
              ],
            ),
          ),
          same
              ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Đã lưu', style: TextStyle(color: Color(0xFF32D583), fontWeight: FontWeight.w700)),
              )
              : TextButton(
                style: TextButton.styleFrom(backgroundColor: C.amber, foregroundColor: C.amberInk, minimumSize: const Size(0, 36)),
                onPressed: () {
                  setState(() {
                    if (name.isNotEmpty) ctName = name;
                    if (ph.isNotEmpty) ctPhone = ph;
                  });
                  HapticFeedback.selectionClick();
                  toast('Đã lưu nhà thầu vào hồ sơ');
                },
                child: const Text('Dùng', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
        ],
      ),
    );
  }

  Widget _round({required VoidCallback onTap, required String label, required Widget child, bool on = false}) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: on ? C.amber : Colors.white.withValues(alpha: .14), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: child,
      ),
    ),
  );

  /// Nhà thầu: khoảng cách (m) từ chỗ chụp tới vị trí dự án; null nếu thiếu toạ độ.
  double? _ntDist() {
    final la = ntPlat, ln = ntPlng;
    if (la == null || ln == null) return null;
    final m = shots.isNotEmpty ? shots.first.meta : const <String, Object>{};
    final lat = m['lat'] is num ? (m['lat'] as num).toDouble() : pos?.lat;
    final lng = m['lng'] is num ? (m['lng'] as num).toDouble() : pos?.lng;
    if (lat == null || lng == null) return null;
    return math.sqrt(math.pow(lat - la, 2) + math.pow((lng - ln) * math.cos(la * math.pi / 180), 2)) * 111320;
  }

  /// Nhà thầu (thiết kế "Xác nhận & tải lên"): công trình + khớp GPS, hạng mục hôm nay, ghi chú.
  List<Widget> _ntConfirm() {
    final d = _ntDist();
    final near = d != null && d <= 200;
    Widget cap(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 0.6)),
        );
    return [
      cap('CÔNG TRÌNH'),
      InkWell(
        borderRadius: BorderRadius.circular(R.ctl),
        onTap: widget.ntPick != null && pct == null ? _pickProject : null,
        child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: ntPid == 0 ? const Color(0xFFFFF7E0) : Colors.white,
            borderRadius: BorderRadius.circular(R.ctl),
            border: Border.all(color: ntPid == 0 ? C.amber : C.line, width: ntPid == 0 ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Row(children: [
            Expanded(
              child: Text(ntPid == 0 ? 'Chọn dự án cho nhật ký' : (ntPname.isNotEmpty ? ntPname : 'Dự án'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text)),
            ),
            if (widget.ntPick != null)
              Text(ntPid == 0 ? 'Chọn' : 'Đổi', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.navy3, decoration: TextDecoration.underline)),
          ]),
          if (d != null)
            Row(spacing: 6, children: [
              Ic(near ? 'check' : 'pin', size: 16, color: near ? C.ok : C.bad),
              Expanded(
                child: Text(
                  near ? 'Khớp vị trí GPS · cách ${d.round()}m' : 'Cách công trình ${d < 1000 ? '${d.round()}m' : '${(d / 1000).toStringAsFixed(1)}km'}, kiểm tra lại đúng dự án chưa',
                  style: TextStyle(fontSize: 13.5, color: near ? C.ok : C.bad, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
        ]),
      ),
      ),
      cap('HẠNG MỤC HÔM NAY'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in _ntCats)
          FilterChip(
            label: Text(c),
            selected: ntCats.contains(c),
            onSelected: pct == null ? (on) => setState(() => on ? ntCats.add(c) : ntCats.remove(c)) : null,
          ),
        ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Khác'), onPressed: pct == null ? () => ntNoteFocus.requestFocus() : null),
      ]),
      cap('GHI CHÚ (KHÔNG BẮT BUỘC)'),
      TextField(
        controller: ntNote,
        focusNode: ntNoteFocus,
        enabled: pct == null,
        maxLines: 3,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Vd: Lắp cốp pha cột tầng 2', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
      ),
    ];
  }

  Widget _review() {
    final sum = checks.tally(shots.map((s) => s.path).toList());
    final total = widget.have + shots.length;
    final nt = _nt;
    final t = DateTime.now();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Container(
        color: C.bg,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          nt
                              ? 'Xác nhận nhật ký'
                              : clips.isEmpty
                                  ? '${shots.length} ảnh vừa chụp'
                                  : '${shots.length} ảnh · ${clips.length} video',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.3),
                        ),
                        if (nt)
                          Text(
                            '${_ntWeek[t.weekday - 1]}, ${p2(t.day)}/${p2(t.month)}/${t.year} · ${p2(t.hour)}:${p2(t.minute)}'
                            '${pos != null ? ' · GPS ±${pos!.acc.round()}m' : ''}',
                            style: T.muted.copyWith(fontSize: 14),
                          )
                        else
                        Text(
                          total >= cfg.minPhotos
                              ? 'Hồ sơ $total ảnh · dự kiến ${money(cfg.payFor(total))}'
                              : 'Cần ít nhất ${cfg.minPhotos} ảnh, còn thiếu ${cfg.minPhotos - total}',
                          style: T.muted.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Đóng, chụp tiếp', onPressed: pct == null ? () => setState(() => review = false) : null, icon: const Ic('x', size: 26)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  PhotoGrid(
                    children: [
                      for (var k = 0; k < shots.length; k++)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(R.ctl),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              localImage(shots[k].path, fit: BoxFit.cover, cacheWidth: 400),
                              DelBtn(icon: 'trash', label: 'Bỏ ảnh ${k + 1}', onTap: pct == null ? () => drop(k) : null),
                              Positioned(
                                left: 8,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                                  child: Text(
                                    '${k + 1}',
                                    style: const TextStyle(
                                      color: C.text,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                              CheckBadge(checks[shots[k].path]),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (clips.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('Video (${clips.length}/$maxVideos)', style: const TextStyle(fontWeight: FontWeight.w600, color: C.text)),
                    for (var k = 0; k < clips.length; k++)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          spacing: 10,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(R.ctl)),
                              alignment: Alignment.center,
                              child: const Ic('video', color: Colors.white, size: 20),
                            ),
                            Expanded(
                              child: Text(
                                'Video ${k + 1}${clips[k].secs > 0 ? ' · ${_clock(clips[k].secs)}' : ''} · ${mb(clips[k].bytes)}',
                                style: const TextStyle(color: C.text, fontSize: 14),
                              ),
                            ),
                            IconButton(tooltip: 'Bỏ video ${k + 1}', onPressed: pct == null ? () => dropClip(k) : null, icon: const Ic('trash', size: 20)),
                          ],
                        ),
                      ),
                    if (videoTip().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(videoTip(), style: T.muted)),
                  ],
                  if (nt) ..._ntConfirm(),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  if (upWhat.isNotEmpty) Text(upWhat, style: T.muted),
                  if (pct != null) Progress(pct: pct!, doneText: upWhat.isNotEmpty ? 'Đã tải xong video.' : 'Đã tải xong. Đang kiểm tra ảnh…'),
                  if (!nt && (ctName.isNotEmpty || ctPhone.isNotEmpty))
                    Row(
                      spacing: 8,
                      children: [
                        const Ic('check', color: C.ok, size: 18),
                        Expanded(
                          child: Text(
                            'Nhà thầu (quét từ bảng hiệu): ${[if (ctName.isNotEmpty) ctName, if (ctPhone.isNotEmpty) prettyPhone(ctPhone)].join(' · ')}',
                            style: const TextStyle(color: C.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(onPressed: pct == null ? () => setState(() => ctName = ctPhone = '') : null, child: const Text('Bỏ')),
                      ],
                    ),
                  if (sum.isNotEmpty)
                    Note(tone: 'wait', icon: 'spark', title: 'AI: $sum', text: 'Ảnh chưa đạt không được tính tiền, bấm thùng rác để bỏ rồi chụp lại.'),
                  if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.bad)),
                  Row(
                    spacing: 8,
                    children: [
                      Btn('Chụp tiếp', icon: 'camera', onPressed: () => setState(() => review = false), disabled: pct != null),
                      Expanded(
                        child: Btn(
                          [if (shots.isNotEmpty) '${shots.length} ảnh', if (clips.isNotEmpty) '${clips.length} video'].isEmpty
                              ? 'Tải lên'
                              : 'Tải lên ${[if (shots.isNotEmpty) '${shots.length} ảnh', if (clips.isNotEmpty) '${clips.length} video'].join(' + ')}',
                          icon: 'upload',
                          kind: BtnKind.primary,
                          onPressed: send,
                          busy: pct != null,
                          disabled: shots.isEmpty && clips.isEmpty,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Khung vàng quanh chữ đọc được (toạ độ 0..1) + vạch thăng bằng khi máy nghiêng.
class _LivePainter extends CustomPainter {
  _LivePainter(this.phone, this.company, this.roll);
  final TextPiece? phone, company;
  final double roll;

  @override
  void paint(Canvas canvas, Size size) {
    final box =
        Paint()
          ..color = C.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
    for (final p in [phone, company]) {
      if (p == null) continue;
      final r = Rect.fromLTRB(p.left * size.width - 4, p.top * size.height - 4, p.right * size.width + 4, p.bottom * size.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), box);
    }
    final a = roll.abs();
    if (a > 3 && a < 60) {
      final c = size.center(Offset.zero), half = size.width * .32;
      final level =
          Paint()
            ..color = (a > 8 ? C.amber : Colors.white).withValues(alpha: .9)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round;
      // vạch ngang thật (theo trọng lực) so với vạch ngang của máy
      final t = -roll * math.pi / 180;
      final d = Offset(math.cos(t) * half, math.sin(t) * half);
      canvas.drawLine(c - d, c + d, level);
      canvas.drawLine(
        c - Offset(half * .25, 0),
        c + Offset(half * .25, 0),
        Paint()
          ..color = Colors.white.withValues(alpha: .5)
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_LivePainter o) => o.phone != phone || o.company != company || (o.roll - roll).abs() > .5;
}
