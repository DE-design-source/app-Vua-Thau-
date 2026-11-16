// Đăng nhập: bằng Google, hoặc bằng số điện thoại + mật khẩu.
import 'package:flutter/material.dart';

import '../api.dart';
import '../auth.dart';
import '../toast.dart';
import '../ui.dart';
import 'register.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController(), pw = TextEditingController();
  bool show = false;
  String busy = '';

  @override
  void initState() {
    super.initState();
    phone.addListener(() => setState(() {}));
    pw.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    phone.dispose();
    pw.dispose();
    super.dispose();
  }

  Future<void> run(String what, Future<void> Function() job) async {
    setState(() => busy = what);
    try {
      await job();
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => busy = '');
    }
  }

  void byPassword() {
    if (phone.text.isEmpty || pw.text.isEmpty || busy.isNotEmpty) return;
    run('pw', () async => signedIn(await post('/auth/login', {'login': phone.text.trim(), 'password': pw.text})));
  }

  void byGoogle() => run('gg', () async {
        final picked = await pickGoogle();
        if (picked == null) return;
        final g = await googleSignIn(picked);
        if (g != null) {
          // Google này chưa có tài khoản: sang đăng ký, điền sẵn tên + email
          pendingGoogle = g;
          toast('${g.email} chưa đăng ký. Điền thêm số điện thoại, mật khẩu, ngân hàng để tạo tài khoản.');
          if (mounted) push(context, const RegisterScreen());
        }
      });

  @override
  Widget build(BuildContext context) {
    final gOn = googleOn();
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
        const AuthTop(title: 'Vua Thầu Nghiệm thu', text: 'Chụp công trình, nhận tiền nhanh.'),
        Lift(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Box(padding: const EdgeInsets.all(20), gap: 16, children: [
              if (gOn) ...[
                GoogleBtn(title: 'Đăng nhập bằng Google', onPressed: byGoogle, busy: busy == 'gg'),
                const Row(spacing: 10, children: [
                  Expanded(child: Divider(color: C.line, height: 1)),
                  Text('hoặc dùng số điện thoại', style: T.muted),
                  Expanded(child: Divider(color: C.line, height: 1)),
                ]),
              ],
              AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                  Field(
                    label: 'Số điện thoại',
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    placeholder: '0901234567',
                    autofill: const [AutofillHints.telephoneNumber],
                  ),
                  Field(
                    label: 'Mật khẩu',
                    controller: pw,
                    obscure: !show,
                    autofill: const [AutofillHints.password],
                    onSubmitted: (_) => byPassword(),
                    suffix: IconButton(
                      tooltip: show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                      onPressed: () => setState(() => show = !show),
                      icon: Ic('eye', color: show ? C.navy3 : C.muted),
                    ),
                  ),
                ]),
              ),
              Btn('Đăng nhập',
                  kind: BtnKind.primary,
                  onPressed: byPassword,
                  busy: busy == 'pw',
                  disabled: phone.text.isEmpty || pw.text.isEmpty || busy.isNotEmpty),
            ]),
          ),
        ),
        InkWell(
          onTap: () {
            pendingGoogle = null;
            push(context, const RegisterScreen());
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text.rich(
              TextSpan(text: 'Cộng tác viên mới? ', children: [
                TextSpan(text: gOn ? 'Đăng ký bằng Google' : 'Đăng ký ngay', style: const TextStyle(fontWeight: FontWeight.w700, color: C.navy3)),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: C.text),
            ),
          ),
        ),
      ]),
    );
  }
}
