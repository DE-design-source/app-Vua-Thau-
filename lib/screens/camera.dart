// Camera nghiệm thu kiểu Timemark (như /chup của web): khung ngắm + GPS + địa chỉ, in dải chữ Timemark lên ảnh.
// Chưa có GPS thì không cho chụp: ảnh nghiệm thu bắt buộc có vị trí.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../check.dart';
import '../lfile.dart';
import '../picker.dart';
import '../stamp.dart';
import '../toast.dart';
import '../ui.dart';
import 'house.dart';
import 'submit.dart' show houseIdOf;

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
  double? pct;
  String err = '';
  final checks = Checks(); // AI kiểm từng ảnh ngay sau khi chụp
  Pos? looked;
  Timer? clock;
  StreamSubscription<Position>? gps;

  int get left => cfg.maxPhotos - widget.have;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checks.addListener(_tick);
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
        cam = null;
        setState(() => camReady = false);
        c.dispose();
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
      final c = CameraController(back, ResolutionPreset.max, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
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
    if (shots.isEmpty || await confirm(context, title: 'Bỏ ảnh vừa chụp?', text: 'Ảnh chưa tải lên sẽ mất.', ok: 'Bỏ ảnh', cancel: 'Ở lại')) {
      for (final s in shots) {
        deleteLocal(s.path);
      }
      shots.clear();
      if (mounted) Navigator.of(context).pop();
    }
  }

  bool get canShoot => camReady && pos != null && !busy && shots.length < left;

  Future<void> shoot() async {
    final c = cam;
    if (!canShoot || c == null) return;
    final date = DateTime.now(), p = pos!, a = addr;
    setState(() => busy = true);
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
      };
      setState(() => shots.add(_Shot(path, meta)));
      checks.run(path, meta: meta);
    } catch (e) {
      toast('Chụp không được: $e');
    } finally {
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
    setState(() {
      err = '';
      pct = 0;
    });
    try {
      final j = await upload(
        widget.hid > 0 ? '/houses/${widget.hid}/photos' : '/houses',
        [for (var k = 0; k < shots.length; k++) UpFile('files', shots[k].path, 'vuathau-${k + 1}.jpg')],
        fields: {'meta': jsonEncode([for (final s in shots) s.meta])},
        onProgress: (p) {
          if (mounted) setState(() => pct = p);
        },
      );
      toast(msgsOf(j));
      final id = houseIdOf(j);
      // hồ sơ mới: house_id null; hồ sơ có sẵn: added = 0
      if (widget.hid > 0 ? j.containsKey('added') && asInt(j['added']) == 0 : id == null) {
        setState(() => err = 'Không ảnh nào được nhận, xem lý do ở trên.');
        return;
      }
      shots.clear();
      if (!mounted) return;
      if (widget.hid > 0 || id == null) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HouseScreen(id: id)));
      }
    } catch (e) {
      if (mounted) setState(() => err = '${errMsg(e)} Ảnh vẫn còn đây.');
    } finally {
      if (mounted) setState(() => pct = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: shots.isEmpty && pct == null,
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
                    ? 'Đủ $min ảnh (${money(cfg.payFor(min))}). Chụp thêm 1 ảnh để được ${money(cfg.payFor(min + 1))}.'
                    : 'Đủ ảnh (${money(cfg.payFor(min + 1))}). Bấm Xong để tải lên.';
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
            Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: C.heroMuted, fontSize: 13.5, height: 1.4)),
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
                    onTap: shots.isEmpty ? null : () => setState(() => review = true),
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
                          child: shots.isEmpty ? const Center(child: Ic('image', color: Colors.white54, size: 22)) : localImage(shots.last.path, fit: BoxFit.cover, cacheWidth: 200),
                        ),
                        if (shots.isNotEmpty)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              height: 22,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.black, width: 1.5)),
                              alignment: Alignment.center,
                              child: Text('${shots.length}',
                                  style: const TextStyle(color: C.amberInk, fontWeight: FontWeight.w700, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
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
                  opacity: shots.isEmpty ? 0.4 : 1,
                  child: Material(
                    color: Colors.transparent,
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      decoration: const ShapeDecoration(gradient: blueGradient, shape: StadiumBorder()),
                      child: InkWell(
                        onTap: shots.isEmpty ? null : () => setState(() => review = true),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Center(
                            widthFactor: 1,
                            child: Text(shots.isNotEmpty ? 'Xong · ${shots.length}' : 'Xong',
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
                  Text('${shots.length} ảnh vừa chụp', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.3)),
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
            ]),
          ),
          Container(
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              if (pct != null) Progress(pct: pct!, doneText: 'Đã tải xong. Đang kiểm tra ảnh…'),
              if (sum.isNotEmpty)
                Note(tone: 'wait', icon: 'spark', title: 'AI: $sum', text: 'Ảnh chưa đạt không được tính tiền, bấm thùng rác để bỏ rồi chụp lại.'),
              if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.bad)),
              Row(spacing: 8, children: [
                Btn('Chụp tiếp', icon: 'camera', onPressed: () => setState(() => review = false), disabled: pct != null),
                Expanded(
                  child: Btn('Tải lên ${shots.length} ảnh', icon: 'upload', kind: BtnKind.primary, onPressed: send, busy: pct != null, disabled: shots.isEmpty),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
