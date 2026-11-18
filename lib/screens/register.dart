// Đăng ký CTV: chọn Google (lấy tên, email) rồi điền SĐT, mật khẩu, tài khoản nhận tiền.
// Mật khẩu để sau này đăng nhập được cả bằng SĐT. CTV cũ: nhập SĐT + mật khẩu cũ là gắn Google vào tài khoản sẵn có.
import 'package:flutter/material.dart';

import '../api.dart';
import '../auth.dart';
import '../toast.dart';
import '../ui.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  GoogleUser? g = pendingGoogle;
  late final name = TextEditingController(text: pendingGoogle?.name ?? '');
  final phone = TextEditingController(), pw = TextEditingController();
  final bank = BankCtl();
  String busy = '';

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    pw.dispose();
    bank.dispose();
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

  void choose() => run('gg', () async {
        final picked = await pickGoogle();
        if (picked == null) return;
        final x = await googleSignIn(picked); // Google này đã có tài khoản: vào luôn (trả null)
        if (x == null) return;
        pendingGoogle = x;
        if (!mounted) return;
        setState(() => g = x);
        if (name.text.isEmpty) name.text = x.name;
      });

  void submit() => run('go', () async {
        final j = await post('/auth/register', {
          if (g != null) 'id_token': g!.idToken,
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'password': pw.text,
          ...bank.toJson(),
        });
        await signedIn(j);
      });

  @override
  Widget build(BuildContext context) {
    final needGoogle = googleOn() && g == null;
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
        AuthTop(
          title: 'Trở thành cộng tác viên',
          text: 'Chụp ảnh công trình đang xây, mỗi căn được ${money(cfg.payFor(cfg.minPhotos))} – ${money(cfg.payFor(cfg.minPhotos + 1))}.',
        ),
        Lift(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Box(
              raised: true,
              padding: const EdgeInsets.all(20),
              gap: 16,
              children: needGoogle
                  ? [
                      const Text('Bước 1: chọn tài khoản Google', style: T.secT),
                      const Text('App lấy tên và email từ Google. Sau đó bạn điền số điện thoại, mật khẩu và tài khoản nhận tiền.', style: T.muted),
                      GoogleBtn(title: 'Đăng ký bằng Google', onPressed: choose, busy: busy == 'gg'),
                    ]
                  : [
                      if (g != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: C.soft, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.field)),
                          child: Row(spacing: 12, children: [
                            Avatar(
                              color: Colors.white,
                              child: Text(initials(g!.name.isNotEmpty ? g!.name : g!.email), style: const TextStyle(fontWeight: FontWeight.w600, color: C.navy3)),
                            ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(g!.name.isNotEmpty ? g!.name : 'Tài khoản Google',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: C.text)),
                                Text(g!.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.muted),
                              ]),
                            ),
                            TextButton(onPressed: busy.isEmpty ? choose : null, child: const Text('Đổi', style: TextStyle(color: C.text, fontWeight: FontWeight.w600, decoration: TextDecoration.underline))),
                          ]),
                        ),
                      Field(label: 'Họ tên', controller: name, capitalization: TextCapitalization.words, autofill: const [AutofillHints.name]),
                      Field(label: 'Số điện thoại', controller: phone, keyboardType: TextInputType.phone, placeholder: '0901234567'),
                      Field(
                        label: 'Mật khẩu',
                        controller: pw,
                        obscure: true,
                        autofill: const [AutofillHints.newPassword],
                        hint: g != null
                            ? 'Ít nhất 6 ký tự, để đăng nhập bằng số điện thoại khi không dùng Google. Đã có tài khoản? Nhập SĐT và mật khẩu cũ để liên kết, không cần điền ngân hàng.'
                            : 'Ít nhất 6 ký tự.',
                      ),
                      const Padding(padding: EdgeInsets.only(top: 8), child: Text('Tài khoản nhận tiền', style: T.secT)),
                      BankFields(c: bank),
                      Btn('Tạo tài khoản', kind: BtnKind.primary, onPressed: submit, busy: busy == 'go', disabled: busy.isNotEmpty),
                    ],
            ),
          ),
        ),
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text.rich(
              TextSpan(text: 'Đã có tài khoản? ', children: [
                TextSpan(text: 'Đăng nhập', style: TextStyle(fontWeight: FontWeight.w600, color: C.text, decoration: TextDecoration.underline)),
              ]),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: C.text),
            ),
          ),
        ),
      ]),
    );
  }
}
