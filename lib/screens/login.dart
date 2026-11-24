// Đăng nhập (góp ý 24/11/2026): chọn "Cộng tác viên" hay "Nhà thầu" rồi nhập số điện thoại (không mật khẩu).
//   CTV: SĐT đã có tài khoản là vào; chưa có thì sang Đăng ký, điền sẵn SĐT. Vẫn giữ Đăng nhập bằng Google.
//   Nhà thầu: tài khoản do Vua Thầu cấp; SĐT chưa có thì mở form Đăng ký nhà thầu.
//   Chọn nhầm vai trò (SĐT là CTV mà chọn Nhà thầu...): máy chủ báo, app gợi ý chuyển đúng vai trò.
// Web: link /app/?as=nhathau&phone=09... (trang đăng nhập web) mở sẵn vai trò + SĐT rồi tự đăng nhập.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth.dart';
import '../ui.dart';
import 'register.dart';

const roleCtv = 'ctv', roleNt = 'nhathau';

class LoginScreen extends StatefulWidget {
  /// role: vai trò chọn sẵn ('ctv' | 'nhathau' | ''); auto: có SĐT thì đăng nhập luôn.
  const LoginScreen({super.key, this.role = '', this.phone = '', this.auto = false});
  final String role, phone;
  final bool auto;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final phone = TextEditingController(text: widget.phone);
  late String role = widget.role == roleCtv || widget.role == roleNt ? widget.role : '';
  String busy = '', err = '', switchTo = '';
  bool ntNew = false; // SĐT chưa có tài khoản nhà thầu: hiện nút Đăng ký nhà thầu
  bool ntPending = false; // đã đăng ký form nhà thầu, Vua Thầu chưa xác minh

  @override
  void initState() {
    super.initState();
    phone.addListener(() => setState(() {
          err = '';
          ntNew = false;
          switchTo = '';
        }));
    if (widget.auto && role.isNotEmpty && phone.text.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => byPhone());
  }

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> run(String what, Future<void> Function() job) async {
    setState(() {
      busy = what;
      err = '';
      switchTo = '';
      ntNew = false;
    });
    try {
      await job();
    } catch (e) {
      final m = errMsg(e);
      if (mounted) {
        setState(() {
          err = m;
          // máy chủ: 'Số ... là tài khoản Nhà thầu. Chọn "Nhà thầu" để đăng nhập.'
          switchTo = m.contains('"Nhà thầu"') ? roleNt : (m.contains('"Cộng tác viên"') ? roleCtv : '');
        });
      }
    } finally {
      if (mounted) setState(() => busy = '');
    }
  }

  bool get ready => role.isNotEmpty && phone.text.replaceAll(RegExp(r'\D'), '').length >= 9 && busy.isEmpty;

  void byPhone() {
    if (!ready) return;
    run('ph', () async {
      final j = await post('/auth/phone', {'phone': phone.text.trim(), 'as': role});
      if (j['registered'] == true) {
        await signedIn(j);
        return;
      }
      if (role == roleNt) {
        if (mounted) {
          setState(() {
            ntNew = true;
            ntPending = j['nt_pending'] == true;
          });
        }
        return;
      }
      // CTV mới: sang đăng ký, điền sẵn SĐT
      pendingGoogle = null;
      if (mounted) push(context, RegisterScreen(phone: '${j['phone'] ?? phone.text.trim()}'));
    });
  }

  void byGoogle() => run('gg', () async {
        final picked = await pickGoogle();
        if (picked == null) return;
        final g = await googleSignIn(picked);
        if (g != null) {
          // Google này chưa có tài khoản: sang đăng ký, điền sẵn tên + email
          pendingGoogle = g;
          if (mounted) push(context, RegisterScreen(phone: phone.text.trim()));
        }
      });

  void pick(String r) => setState(() {
        role = r;
        err = '';
        switchTo = '';
        ntNew = false;
      });

  Widget _roleCard(String r, IconData icon, String title, String sub) {
    final on = role == r;
    return Expanded(
      child: Semantics(
        selected: on,
        button: true,
        child: Material(
          color: on ? const Color(0xFFFFF7E0) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: on ? C.amber : C.line, width: on ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: busy.isEmpty ? () => pick(r) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: on ? C.amber : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: on ? C.amberInk : C.navy, size: 22),
                  ),
                  const Spacer(),
                  Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? C.amberInk : C.subtle, size: 20),
                ]),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
                Text(sub, style: const TextStyle(fontSize: 12, height: 1.3, color: C.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gOn = googleOn() && role == roleCtv;
    return Scaffold(
      appBar: Navigator.of(context).canPop()
          ? AppBar(backgroundColor: const Color(0xFF0B2340), foregroundColor: Colors.white, elevation: 0, toolbarHeight: 44)
          : null,
      body: ListView(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const AuthTop(title: 'Đăng nhập Vua Thầu Map', text: 'Chọn bạn là Cộng tác viên hay Nhà thầu, rồi nhập số điện thoại.'),
          Lift(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Box(
                padding: const EdgeInsets.all(18),
                gap: 14,
                children: [
                  const Text('Bạn là', style: T.formHead),
                  Row(spacing: 10, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _roleCard(roleCtv, Icons.photo_camera_outlined, 'Cộng tác viên', 'Chụp công trình, nhận tiền về tài khoản'),
                    _roleCard(roleNt, Icons.engineering_outlined, 'Nhà thầu', 'Nhật ký thi công, hồ sơ năng lực'),
                  ]),
                  if (role.isNotEmpty) ...[
                    Field(
                      label: 'Số điện thoại',
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      placeholder: '0901234567',
                      autofill: const [AutofillHints.telephoneNumber],
                      onSubmitted: (_) => byPhone(),
                      hint: role == roleCtv ? 'Chưa có tài khoản thì app chuyển sang đăng ký.' : 'Số điện thoại Vua Thầu đã cấp cho công ty bạn.',
                    ),
                    if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.bad, fontSize: 13.5, height: 1.35)),
                    if (switchTo.isNotEmpty)
                      Btn(
                        switchTo == roleNt ? 'Chuyển sang Nhà thầu và đăng nhập' : 'Chuyển sang Cộng tác viên và đăng nhập',
                        onPressed: () {
                          pick(switchTo);
                          byPhone();
                        },
                      ),
                    if (ntNew)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: C.amberBg, borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                          Text(ntPending ? 'Vua Thầu đang xác minh hồ sơ nhà thầu của bạn.' : 'Số này chưa có tài khoản nhà thầu.',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: C.text)),
                          Text(
                              ntPending
                                  ? 'Đã nhận đăng ký của số này. Xác minh xong, tài khoản tự có, bạn nhập lại số này để vào.'
                                  : 'Đăng ký nhà thầu, Vua Thầu xác minh xong là tài khoản tự có theo số điện thoại này.',
                              style: T.muted),
                          if (cfg.ntForm.isNotEmpty && !ntPending)
                            Btn('Đăng ký nhà thầu', icon: 'right', onPressed: () => launchUrl(Uri.parse(cfg.ntForm), mode: LaunchMode.externalApplication)),
                        ]),
                      ),
                    Btn('Tiếp tục', kind: BtnKind.primary, onPressed: byPhone, busy: busy == 'ph', disabled: !ready),
                    if (gOn) ...[
                      Row(
                        spacing: 10,
                        children: [
                          const Expanded(child: Divider(color: C.line, height: 1)),
                          Text('hoặc', style: T.hint.copyWith(color: C.subtle)),
                          const Expanded(child: Divider(color: C.line, height: 1)),
                        ],
                      ),
                      GoogleBtn(title: 'Đăng nhập bằng Google', onPressed: byGoogle, busy: busy == 'gg'),
                    ],
                  ] else
                    const Text('Chọn 1 trong 2 ô trên để tiếp tục.', style: T.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
