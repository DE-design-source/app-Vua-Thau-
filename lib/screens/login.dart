// Đăng nhập (góp ý 20/11/2026): chỉ cần số điện thoại. SĐT đã có tài khoản CTV là vào luôn;
// chưa có thì sang Đăng ký, điền sẵn SĐT. Vẫn giữ Đăng nhập bằng Google cho ai đã gắn Google.
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
  final phone = TextEditingController();
  String busy = '';

  @override
  void initState() {
    super.initState();
    phone.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    phone.dispose();
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

  bool get ready => phone.text.replaceAll(RegExp(r'\D'), '').length >= 9 && busy.isEmpty;

  void byPhone() {
    if (!ready) return;
    run('ph', () async {
      final j = await post('/auth/phone', {'phone': phone.text.trim()});
      if (j['registered'] == true) {
        await signedIn(j);
        return;
      }
      // SĐT chưa có tài khoản: sang đăng ký, điền sẵn SĐT
      pendingGoogle = null;
      toast('Số này chưa có tài khoản. Điền họ tên và tài khoản nhận tiền để đăng ký.');
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
      toast('${g.email} chưa đăng ký. Điền thêm số điện thoại và ngân hàng để tạo tài khoản.');
      if (mounted) push(context, RegisterScreen(phone: phone.text.trim()));
    }
  });

  @override
  Widget build(BuildContext context) {
    final gOn = googleOn();
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const AuthTop(title: 'Nghiệm thu công trình', text: 'Chụp công trình đang xây, AI kiểm ảnh, nhận tiền về tài khoản.'),
          Lift(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Box(
                padding: const EdgeInsets.all(20),
                gap: 16,
                children: [
                  const Text('Đăng nhập', style: T.formHead),
                  Field(
                    label: 'Số điện thoại',
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    placeholder: '0901234567',
                    autofill: const [AutofillHints.telephoneNumber],
                    onSubmitted: (_) => byPhone(),
                    hint: 'Chưa có tài khoản thì app chuyển sang đăng ký.',
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
