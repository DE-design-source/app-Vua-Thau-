import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'page.dart';
import 'screens/home_shell.dart';
import 'screens/login.dart';
import 'toast.dart';
import 'ui.dart';

final navKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const VuaThauApp());
}

class VuaThauApp extends StatelessWidget {
  const VuaThauApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vua Thầu Nghiệm thu',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: C.navy, primary: C.navy, secondary: C.amber, surface: Colors.white),
        scaffoldBackgroundColor: C.bg,
        textSelectionTheme: const TextSelectionThemeData(cursorColor: C.navy3),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.navy),
      ),
      builder: (context, child) => ToastHost(child: child ?? const SizedBox()),
      home: const Boot(),
    );
  }
}

/// Lấy cấu hình máy chủ + token đã lưu, rồi mở Đăng nhập hoặc app.
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  String state = 'wait'; // wait | ok | off

  @override
  void initState() {
    super.initState();
    // Đăng nhập / đăng xuất / hết phiên: đóng mọi màn đang mở, về màn gốc.
    authed.addListener(_reset);
    run();
  }

  @override
  void dispose() {
    authed.removeListener(_reset);
    super.dispose();
  }

  void _reset() {
    tabIndex.value = 0;
    navKey.currentState?.popUntil((r) => r.isFirst);
  }

  Future<void> run() async {
    setState(() => state = 'wait');
    try {
      await start();
      if (mounted) setState(() => state = 'ok');
      checkUpdate();
    } catch (_) {
      if (mounted) setState(() => state = 'off');
    }
  }

  /// App cài từ link Zalo (APK) không tự cập nhật: hỏi máy chủ bản mới nhất, mới hơn thì mời tải về cài đè.
  Future<void> checkUpdate() async {
    if (kDebugMode) return;
    try {
      final mine = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      final r = await http.get(Uri.parse('$host/tai-app/phien-ban')).timeout(const Duration(seconds: 10));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final code = (j['code'] as num?)?.toInt() ?? 0;
      final ctx = navKey.currentContext;
      if (code <= mine || ctx == null || !ctx.mounted) return;
      final ok = await confirm(ctx,
          title: 'Có bản app mới',
          text: 'Bản ${j['version']} đã có. Tải về và cài đè lên, tài khoản và hồ sơ vẫn giữ nguyên.',
          ok: 'Tải về',
          cancel: 'Để sau',
          danger: false);
      if (ok) await launchUrl(Uri.parse('$host/tai-app'), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (state == 'wait') {
      return const Scaffold(backgroundColor: C.navy, body: Center(child: Brand(size: 72)));
    }
    if (state == 'off') {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: C.navy,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, spacing: 16, children: [
                const Ic('alert', color: C.amber, size: 40),
                const Text('Không kết nối được máy chủ',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const Text('Kiểm tra Wi-Fi hoặc 4G rồi thử lại.', textAlign: TextAlign.center, style: TextStyle(color: C.heroMuted)),
                Btn('Thử lại', kind: BtnKind.primary, onPressed: run),
              ]),
            ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: authed,
      builder: (context, ok, _) => ok ? const HomeShell() : const LoginScreen(),
    );
  }
}
