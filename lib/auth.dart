import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io' show Platform;

import 'api.dart';
import 'toast.dart';
import 'ui.dart';

/// Đầu trang đăng nhập / đăng ký: logo + câu chào trên nền navy.
class AuthTop extends StatelessWidget {
  const AuthTop({super.key, required this.title, required this.text});
  final String title, text;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Container(
          color: C.navy,
          padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 32, 24, 56),
          child: Column(spacing: 10, children: [
            const Brand(size: 56),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.heroMuted, fontSize: 15)),
          ]),
        ),
      );
}

/// Sau đăng nhập / đăng ký: app chỉ dành cho CTV, admin và kế toán dùng web.
Future<void> signedIn(Json j) async {
  final token = j['token'];
  if (token is String && j['url'] == '/cua-toi') {
    toast(msgsOf(j)); // token đã lưu: màn gốc tự mở màn Hồ sơ
    return;
  }
  if (token is String) {
    await setToken(null);
    toast('App dành cho cộng tác viên. Admin và kế toán dùng web nghiemthu.vuathau.com.vn.');
    return;
  }
  final ms = msgsOf(j);
  toast(ms.isNotEmpty ? ms : 'Chưa đăng nhập được, thử lại nhé.');
}

// ---------- Google ----------
// App lấy id_token từ Google rồi gửi máy chủ; máy chủ hỏi Google để xác minh.
// webClientId lấy từ máy chủ (/app.json): máy chủ chưa cấu hình thì app ẩn nút Google.

class GoogleUser {
  const GoogleUser(this.idToken, this.email, this.name);
  final String idToken, email, name;
}

/// Tài khoản Google vừa chọn nhưng chưa đăng ký: Đăng nhập chuyển sang Đăng ký kèm thông tin này.
GoogleUser? pendingGoogle;

bool googleOn() => Platform.isAndroid && cfg.google.isNotEmpty;

bool _gInit = false;

/// Mở hộp chọn tài khoản Google. Trả null nếu người dùng bấm huỷ.
Future<GoogleUser?> pickGoogle() async {
  final gs = GoogleSignIn.instance;
  try {
    if (!_gInit) {
      await gs.initialize(serverClientId: cfg.google);
      _gInit = true;
    }
    try {
      await gs.signOut(); // luôn hiện danh sách tài khoản để CTV chọn đúng
    } catch (_) {}
    final acc = await gs.authenticate();
    final id = acc.authentication.idToken;
    if (id == null) throw ApiError('Google không trả mã xác minh');
    return GoogleUser(id, acc.email, acc.displayName ?? '');
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) return null;
    throw ApiError('Chưa đăng nhập được Google (${e.description ?? e.code.name}).');
  }
}

const _gLogo = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
    '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>'
    '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>'
    '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>'
    '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>'
    '</svg>';

/// Nút theo hướng dẫn thương hiệu của Google: nền trắng, viền xám, logo G 4 màu.
class GoogleBtn extends StatelessWidget {
  const GoogleBtn({super.key, required this.title, required this.onPressed, this.busy = false});
  final String title;
  final VoidCallback onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFDADCE0))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 12, children: [
              if (busy)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
              else
                SvgPicture.string(_gLogo, width: 20, height: 20),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1F1F1F))),
            ]),
          ),
        ),
      );
}

// ---------- 3 ô tài khoản nhận tiền (dùng ở Đăng ký và Tài khoản) ----------
class BankCtl {
  BankCtl({String name = '', String no = '', String owner = ''})
      : name = TextEditingController(text: name),
        no = TextEditingController(text: no),
        owner = TextEditingController(text: owner);
  final TextEditingController name, no, owner;
  Map<String, String> toForm() => {'bank_name': name.text.trim(), 'bank_no': no.text.trim(), 'bank_owner': owner.text.trim()};
  void dispose() {
    name.dispose();
    no.dispose();
    owner.dispose();
  }
}

class BankFields extends StatelessWidget {
  const BankFields({super.key, required this.c});
  final BankCtl c;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Field(label: 'Ngân hàng', controller: c.name, placeholder: 'Vietcombank, MB Bank…'),
          ListenableBuilder(
            listenable: c.name,
            builder: (context, _) {
              final q = c.name.text.trim().toLowerCase();
              final tips = cfg.banks.where((b) => b.toLowerCase().contains(q) && b != c.name.text).take(q.isEmpty ? 8 : 6).toList();
              if (tips.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tips.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, k) => ActionChip(
                    label: Text(tips[k], style: const TextStyle(fontSize: 14, color: C.text)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: C.line),
                    shape: const StadiumBorder(),
                    onPressed: () {
                      c.name.text = tips[k];
                      c.name.selection = TextSelection.collapsed(offset: tips[k].length);
                    },
                  ),
                ),
              );
            },
          ),
        ]),
        Field(label: 'Số tài khoản', controller: c.no, keyboardType: TextInputType.number, placeholder: '0123456789'),
        Field(
          label: 'Tên chủ tài khoản',
          controller: c.owner,
          capitalization: TextCapitalization.characters,
          formatters: [TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase()))],
          placeholder: 'NGUYEN VAN A',
          hint: 'Ghi đúng như trên thẻ, không dấu. Kế toán chuyển tiền vào tài khoản này.',
        ),
      ]);
}
