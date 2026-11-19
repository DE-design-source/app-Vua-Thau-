// Camera nghiệm thu kiểu Timemark (như /chup của web): khung ngắm + GPS + địa chỉ, in dải chữ Timemark lên ảnh.
// Chưa có GPS thì không cho chụp: ảnh nghiệm thu bắt buộc có vị trí.
// Trợ lý khung ngắm (app Android, lib/live): đọc chữ trên khung hình ngay trên máy, khoanh SĐT + tên nhà thầu trên
// bảng hiệu (bấm Dùng hoặc chụp trúng là lưu vào hồ sơ), nhắc tối / rung tay / nghiêng / chĩa xuống đất, nhắc chụp bảng hiệu.
// Chế độ VIDEO: quay ngay trong màn hình (tối đa 3 phút / video, 5 video / hồ sơ; bản web mở máy quay của điện thoại),
// video lưu tạm, tải lên cùng hồ sơ khi bấm Tải lên (hồ sơ có video được cộng thưởng).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
import 'submit.dart' show houseIdOf;

class _Clip {
  _Clip(this.path, this.name, this.bytes, this.secs);
  final String path, name;
  final int bytes, secs;
}

const _maxClip = Duration(minutes: 3);

class _Shot {
  _Shot(this.path, this.meta);
  final String path;
  final Map<String, Object> meta;
}

bool _far(Pos? a, Pos b) =>
    a == null || math.sqrt(math.pow(a.lat - b.lat, 2) + math.pow((a.lng - b.lng) * math.cos(b.lat * math.pi / 180), 2)) * 111320 > 25;

class CameraScreen extends StatefulWidget {
  /// hid = 0: hồ sơ mới. have: số ảnh hồ sơ đã có.
  const CameraScreen({super.key, this.hid = 0, this.have = 0});
  final int hid, have;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? cam;
  bool camReady = false, denied = false;
  Pos? pos;
  String gpsErr = '', addr = '';
  DateTime now = DateTime.now();
  final shots = <_Shot>[];
  bool busy = false, review = false, torch = false;
  final clips = <_Clip>[]; // video vừa quay, chưa tải lên
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
      final all = await availableCameras();
      if (all.isEmpty) throw CameraException('none', 'Máy không có camera');
      final back = all.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => all.first);
      final c = CameraController(back, ResolutionPreset.max, enableAudio: false, imageFormatGroup: liveImageFormat());
      await c.initialize();
      // bản web: trình duyệt có thể không khoá xoay / không có đèn, bỏ qua
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      try {
        await c.setFlashMode(torch ? FlashMode.torch : FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        cam = c;
        camReady = true;
        denied = false;
      });
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
    } catch (_) {/* mất mạng: ảnh vẫn có toạ độ */}
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

  String _clock(int s) => '${p2(s ~/ 60)}:${p2(s % 60)}';

  bool get canShoot => camReady && pos != null && !busy && shots.length < left;

  Future<void> shoot() async {
    final c = cam;
    if (!canShoot || c == null) return;
    final date = DateTime.now(), p = pos!, a = addr;
    // chụp trúng bảng hiệu: giữ SĐT / tên đang thấy cho ảnh này
    final seenPhone = live.phone, seenName = live.company;
    setState(() => busy = true);
    live.paused = true;
    HapticFeedback.mediumImpact();
    try {
      final raw = await c.takePicture();
      final path = await stampPhoto(raw.path, StampData(date, p, a));
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
      if (firstSign) toast('Đã lưu nhà thầu từ bảng hiệu: ${[if (seenName.isNotEmpty) seenName, if (seenPhone.isNotEmpty) prettyPhone(seenPhone)].join(' · ')}');
      checks.run(path, meta: meta);
    } catch (e) {
      toast('Chụp không được: $e');
    } finally {
      live.paused = false;
      if (mounted) setState(() => busy = false);
    }
  }

  void drop(int k) {
    deleteLocal(shots[k].path);
    setState(() {
      shots.removeAt(k);
      if (shots.isEmpty) review = false;
    });
  }

  Future<void> send() async {
    if (recording) await _stopRec();
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
        final j = await upload('/houses/$id/videos', [UpFile('files', v.path, v.name, videoMime(v.name))], onProgress: (p) {
          if (mounted) setState(() => pct = p);
        });
        if (msgsOf(j).isNotEmpty) toast(msgsOf(j));
        deleteLocal(v.path);
        setState(() => clips.removeAt(0));
      }
      if (!mounted) return;
      final hid = id;
      if (widget.hid > 0 || hid == null) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HouseScreen(id: hid)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => err = doneHid != null && shots.isEmpty
            ? '${errMsg(e)} Ảnh đã lên hồ sơ; video vẫn còn đây, bấm Tải lên để thử lại.'
            : '${errMsg(e)} Ảnh vẫn còn đây.');
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
              {...shots[k].meta, if (k == 0 && ctName.isNotEmpty) 'ct_name': ctName, if (k == 0 && ctPhone.isNotEmpty) 'ct_phone': ctPhone}
          ])
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
        canPop: shots.isEmpty && clips.isEmpty && pct == null && !recording,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (review) {
            if (pct == null) setState(() => review = false);
          } else {
            leave();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: denied ? _denied() : Stack(children: [_camera(), if (review) _review()]),
        ),
      ),
    );
  }

  Widget _denied() => Container(
        decoration: const BoxDecoration(gradient: navyGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Ic('camera', color: C.amber, size: 34),
                  ),
                ),
                const Text('Chưa cho phép Camera',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                const Text('Cho app dùng camera để chụp ảnh nghiệm thu. Bạn vẫn có thể chọn ảnh có sẵn.',
                    textAlign: TextAlign.center, style: TextStyle(color: C.heroMuted, height: 1.45)),
                const SizedBox(height: 6),
                Btn('Mở cài đặt để cho phép', kind: BtnKind.primary, onPressed: () => Geolocator.openAppSettings()),
                Btn('Thử lại', onPressed: _openCam),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Quay lại', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _camera() {
    final n = widget.have + shots.length, min = cfg.minPhotos;
    final last = shots.isNotEmpty ? checks[shots.last.path] : null;
    final p = pos;
    final hint = p == null
        ? (gpsErr.isNotEmpty ? 'Ảnh nghiệm thu bắt buộc có vị trí. Bật quyền Vị trí cho app trong cài đặt máy.' : 'Đang chờ GPS để chụp. Ảnh nghiệm thu bắt buộc có vị trí.')
        : shots.length >= left
            ? 'Đã đủ số ảnh tối đa của hồ sơ. Bấm Xong để tải lên.'
            : n < min
                ? 'Chụp thêm ${min - n} ảnh nữa để đủ $min ảnh.'
                : n == min
                    ? 'Đủ $min ảnh (${money(cfg.payFor(min))}). Chụp thêm 1 ảnh để được ${money(cfg.payFor(min + 1))}. ${videoTip()}'.trim()
                    : 'Đủ ảnh (${money(cfg.payFor(min + 1))}). Bấm Xong để tải lên. ${videoTip()}'.trim();
    final (gpsCol, gpsText) = p == null
        ? (const Color(0xFFFF7A66), gpsErr.isNotEmpty ? gpsErr : 'Đang tìm GPS…')
        : p.acc <= 30
            ? (const Color(0xFF32D583), 'GPS ±${p.acc.round()}m')
            : p.acc <= 100
                ? (C.amber, 'GPS ±${p.acc.round()}m')
                : (const Color(0xFFFF7A66), 'GPS yếu ±${p.acc.round()}m, ra chỗ thoáng');
    final goal = min + 1; // đủ ảnh để được mức tiền cao nhất
    // viên tròn mờ trên nền đen
    BoxDecoration glass([Color? border]) => BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
          border: border != null ? Border.all(color: border.withValues(alpha: .7)) : null,
        );

    return SafeArea(
      child: Column(children: [
        // ---- thanh trên: đóng, đèn | GPS | số ảnh ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(spacing: 8, children: [
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
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 7, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: gpsCol, shape: BoxShape.circle)),
                      Flexible(
                        child: Text(gpsText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: glass(n >= min ? const Color(0xFF32D583) : null),
              alignment: Alignment.center,
              child: Text('$n/$min ảnh',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
        // ---- khung ngắm 3:4 ----
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            // Khung ngắm 3:4 (cảm biến 4:3, cầm dọc), vừa khít vùng trống, không cắt ảnh: thấy gì chụp nấy
            final fw = math.min(box.maxWidth, box.maxHeight * 3 / 4), fh = fw * 4 / 3;
            final c = cam;
            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(R.card),
                child: SizedBox(
                  width: fw,
                  height: fh,
                  child: Stack(fit: StackFit.expand, children: [
                    if (c != null && camReady)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(width: fw, height: fw * c.value.aspectRatio, child: CameraPreview(c)),
                      )
                    else
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                    IgnorePointer(child: CustomPaint(painter: StampPainter(StampData(now, pos, addr)))),
                    IgnorePointer(child: CustomPaint(painter: _LivePainter(live.phoneBox, live.companyBox, live.roll))),
                    if (recording && recAt != null)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(999)),
                          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                            Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFFE5322D), shape: BoxShape.circle)),
                            Text('${_clock(now.difference(recAt!).inSeconds.clamp(0, 9999))} / ${_clock(_maxClip.inSeconds)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                          ]),
                        ),
                      ),
                    Positioned(left: 10, right: 10, top: 10, child: _liveTop()),
                    if (busy)
                      Container(
                        color: Colors.black.withValues(alpha: .35),
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [
                          CircularProgressIndicator(color: Colors.white),
                          Text('Đang in giờ, vị trí lên ảnh…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ]),
                ),
              ),
            );
          }),
        ),
        // ---- tiến độ đủ ảnh + kết quả AI ảnh vừa chụp + gợi ý ----
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(spacing: 10, children: [
            Segs(n: n, total: goal, dark: true),
            if (last != null)
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: switch (last.state) {
                      CheckState.ok => C.okBg,
                      CheckState.bad => C.badBg,
                      _ => Colors.white.withValues(alpha: .14),
                    },
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Ảnh ${shots.length}: ${last.text}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: switch (last.state) {
                        CheckState.ok => C.ok,
                        CheckState.bad => C.bad,
                        _ => Colors.white,
                      },
                    ),
                  ),
                ),
              ),
            if (_coach() case final tip?)
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(999)),
                  child: Text(tip, textAlign: TextAlign.center, style: const TextStyle(color: C.amberInk, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              ),
            Text(
                videoMode
                    ? (clips.length >= maxVideos
                        ? 'Đã đủ $maxVideos video. Bấm Xong để tải lên.'
                        : 'Quay 1 vòng quanh công trình, tối đa 3 phút. ${videoTip()}'.trim())
                    : hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.heroMuted, fontSize: 13.5, height: 1.4)),
            // ---- chuyển chế độ: ẢNH | VIDEO ----
            Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
              for (final (v, label) in [(false, 'ẢNH'), (true, 'VIDEO')])
                GestureDetector(
                  onTap: recording || busy ? null : () => setState(() => videoMode = v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: videoMode == v ? Colors.white : Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
                    child: Text(label,
                        style: TextStyle(color: videoMode == v ? Colors.black : Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: .6)),
                  ),
                ),
            ]),
          ]),
        ),
        // ---- ảnh vừa chụp | nút chụp | Xong ----
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Row(children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Xem ảnh vừa chụp',
                  child: GestureDetector(
                    onTap: shots.isEmpty && clips.isEmpty ? null : () => setState(() => review = true),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: Stack(clipBehavior: Clip.none, children: [
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
                          child: shots.isNotEmpty
                              ? localImage(shots.last.path, fit: BoxFit.cover, cacheWidth: 200)
                              : Center(child: Ic(clips.isNotEmpty ? 'video' : 'image', color: Colors.white54, size: 22)),
                        ),
                        if (shots.isNotEmpty || clips.isNotEmpty)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              height: 22,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.black, width: 1.5)),
                              alignment: Alignment.center,
                              child: Text('${shots.length + clips.length}',
                                  style: const TextStyle(color: C.amberInk, fontWeight: FontWeight.w700, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                            ),
                          ),
                      ]),
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
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      alignment: Alignment.center,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: recording ? 32 : 64,
                        height: recording ? 32 : 64,
                        decoration: BoxDecoration(color: const Color(0xFFE5322D), borderRadius: BorderRadius.circular(recording ? 8 : 32)),
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
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      alignment: Alignment.center,
                      child: Container(
                        width: 64,
                        height: 64,
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
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: shots.isEmpty && clips.isEmpty || recording ? 0.4 : 1,
                  child: Material(
                    color: Colors.transparent,
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      decoration: const ShapeDecoration(gradient: blueGradient, shape: StadiumBorder()),
                      child: InkWell(
                        onTap: shots.isEmpty && clips.isEmpty || recording ? null : () => setState(() => review = true),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Center(
                            widthFactor: 1,
                            child: Text(shots.isNotEmpty || clips.isNotEmpty ? 'Xong · ${shots.length + clips.length}' : 'Xong',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
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
      child: Row(spacing: 8, children: [
        const Ic('spark', color: C.amber, size: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('BẢNG HIỆU', style: TextStyle(color: C.amber, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .5)),
            if (name.isNotEmpty)
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.25)),
            if (ph.isNotEmpty)
              Text(prettyPhone(ph),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
        same
            ? const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Đã lưu', style: TextStyle(color: Color(0xFF32D583), fontWeight: FontWeight.w700)))
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
      ]),
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

  Widget _review() {
    final sum = checks.tally(shots.map((s) => s.path).toList());
    final total = widget.have + shots.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Container(
        color: C.bg,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                  Text(clips.isEmpty ? '${shots.length} ảnh vừa chụp' : '${shots.length} ảnh · ${clips.length} video',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.3)),
                  Text(
                    total >= cfg.minPhotos ? 'Hồ sơ $total ảnh · dự kiến ${money(cfg.payFor(total))}' : 'Cần ít nhất ${cfg.minPhotos} ảnh, còn thiếu ${cfg.minPhotos - total}',
                    style: T.muted.copyWith(fontSize: 14),
                  ),
                ]),
              ),
              IconButton(tooltip: 'Đóng, chụp tiếp', onPressed: pct == null ? () => setState(() => review = false) : null, icon: const Ic('x', size: 26)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
              PhotoGrid(children: [
                for (var k = 0; k < shots.length; k++)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(R.ctl),
                    child: Stack(fit: StackFit.expand, children: [
                      localImage(shots[k].path, fit: BoxFit.cover, cacheWidth: 400),
                      DelBtn(icon: 'trash', label: 'Bỏ ảnh ${k + 1}', onTap: pct == null ? () => drop(k) : null),
                      Positioned(
                        left: 8,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                          child: Text('${k + 1}', style: const TextStyle(color: C.text, fontSize: 11, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                        ),
                      ),
                      CheckBadge(checks[shots[k].path]),
                    ]),
                  ),
              ]),
              if (clips.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Video (${clips.length}/$maxVideos)', style: const TextStyle(fontWeight: FontWeight.w600, color: C.text)),
                for (var k = 0; k < clips.length; k++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(spacing: 10, children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(R.ctl)),
                        alignment: Alignment.center,
                        child: const Ic('video', color: Colors.white, size: 20),
                      ),
                      Expanded(
                        child: Text('Video ${k + 1}${clips[k].secs > 0 ? ' · ${_clock(clips[k].secs)}' : ''} · ${mb(clips[k].bytes)}',
                            style: const TextStyle(color: C.text, fontSize: 14)),
                      ),
                      IconButton(tooltip: 'Bỏ video ${k + 1}', onPressed: pct == null ? () => dropClip(k) : null, icon: const Ic('trash', size: 20)),
                    ]),
                  ),
                if (videoTip().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(videoTip(), style: T.muted)),
              ],
            ]),
          ),
          Container(
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              if (upWhat.isNotEmpty) Text(upWhat, style: T.muted),
              if (pct != null) Progress(pct: pct!, doneText: upWhat.isNotEmpty ? 'Đã tải xong video.' : 'Đã tải xong. Đang kiểm tra ảnh…'),
              if (ctName.isNotEmpty || ctPhone.isNotEmpty)
                Row(spacing: 8, children: [
                  const Ic('check', color: C.ok, size: 18),
                  Expanded(
                    child: Text('Nhà thầu (quét từ bảng hiệu): ${[if (ctName.isNotEmpty) ctName, if (ctPhone.isNotEmpty) prettyPhone(ctPhone)].join(' · ')}',
                        style: const TextStyle(color: C.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(onPressed: pct == null ? () => setState(() => ctName = ctPhone = '') : null, child: const Text('Bỏ')),
                ]),
              if (sum.isNotEmpty)
                Note(tone: 'wait', icon: 'spark', title: 'AI: $sum', text: 'Ảnh chưa đạt không được tính tiền, bấm thùng rác để bỏ rồi chụp lại.'),
              if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.bad)),
              Row(spacing: 8, children: [
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
                      disabled: shots.isEmpty && clips.isEmpty),
                ),
              ]),
            ]),
          ),
        ]),
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
    final box = Paint()
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
      final level = Paint()
        ..color = (a > 8 ? C.amber : Colors.white).withValues(alpha: .9)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      // vạch ngang thật (theo trọng lực) so với vạch ngang của máy
      final t = -roll * math.pi / 180;
      final d = Offset(math.cos(t) * half, math.sin(t) * half);
      canvas.drawLine(c - d, c + d, level);
      canvas.drawLine(c - Offset(half * .25, 0), c + Offset(half * .25, 0), Paint()
        ..color = Colors.white.withValues(alpha: .5)
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_LivePainter o) => o.phone != phone || o.company != company || (o.roll - roll).abs() > .5;
}
