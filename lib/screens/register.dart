// Tạo tài khoản (góp ý slide 24/11/2026): "Bạn là" Cộng tác viên / Nhà thầu / Tổ đội, mỗi lựa chọn hiện bộ trường riêng.
//   CTV: họ tên, SĐT, địa chỉ, tài khoản nhận tiền -> vào app ngay (không mật khẩu, lần sau nhập SĐT là vào).
//   Tổ đội: như CTV + tên công ty / tổ đội + hạng mục thực hiện -> vào app ngay (loại "Tổ đội").
//   Nhà thầu: họ tên, SĐT, tên công ty, hạng mục, địa chỉ -> gửi đăng ký, Vua Thầu xác minh xong mới có tài khoản.
// Đến từ Đăng nhập bằng Google (Google chưa có tài khoản): kèm tên, email Google (chỉ CTV / Tổ đội).
import 'package:flutter/material.dart';

import '../api.dart';
import '../auth.dart';
import '../toast.dart';
import '../ui.dart';
import 'nt_form.dart' show divisions, pickFrom;

const roleCtvReg = 'ctv', roleNtReg = 'nhathau', roleTeamReg = 'todoi';
const _cats = ['Nhà phố', 'Biệt thự', 'Căn hộ', 'Sửa chữa', 'Văn phòng', 'Nội thất'];

class RegisterScreen extends StatefulWidget {
  /// role: lựa chọn chọn sẵn ('ctv' | 'nhathau' | 'todoi'), vd đến từ Đăng nhập chọn "Nhà thầu".
  const RegisterScreen({super.key, this.phone = '', this.role = roleCtvReg});
  final String phone, role;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  GoogleUser? g = pendingGoogle;
  late final name = TextEditingController(text: pendingGoogle?.name ?? '');
  late final phone = TextEditingController(text: widget.phone);
  final company = TextEditingController(), street = TextEditingController();
  final bank = BankCtl();
  late String role = const [roleCtvReg, roleNtReg, roleTeamReg].contains(widget.role) ? widget.role : roleCtvReg;
  String prov = '', ward = '', busy = '', sent = '';
  final cats = <String>{};

  bool get pays => role != roleNtReg; // CTV, tổ đội: nhận tiền chụp công trình
  bool get firm => role != roleCtvReg; // nhà thầu, tổ đội: công ty + hạng mục

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    company.dispose();
    street.dispose();
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

  Future<void> chooseProv() async {
    try {
      final ds = await divisions();
      if (!mounted) return;
      final v = await pickFrom(context, 'Tỉnh / Thành phố', [for (final d in ds) d.name], hint: 'Tìm tỉnh, thành phố');
      if (v != null && v != prov) setState(() => (prov = v, ward = ''));
    } catch (e) {
      toast(errMsg(e));
    }
  }

  Future<void> chooseWard() async {
    if (prov.isEmpty) {
      toast('Chọn tỉnh / thành phố trước.');
      return;
    }
    try {
      final d = (await divisions()).where((x) => x.name == prov).firstOrNull;
      if (d == null || !mounted) return;
      final v = await pickFrom(context, 'Phường / Xã · ${d.name}', d.wards, hint: 'Tìm phường, xã');
      if (v != null) setState(() => ward = v);
    } catch (e) {
      toast(errMsg(e));
    }
  }

  void submit() => run('go', () async {
    final base = {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'province': prov,
      'ward': ward,
      'street': street.text.trim(),
      if (firm) 'company': company.text.trim(),
      if (firm) 'categories': [for (final c in _cats) if (cats.contains(c)) c],
    };
    if (role == roleNtReg) {
      if (company.text.trim().isEmpty) throw ApiError('Nhập tên công ty.');
      final j = await post('/auth/register-nt', base);
      if (mounted) setState(() => sent = str(j['message']));
      return;
    }
    final j = await post('/auth/register', {if (g != null) 'id_token': g!.idToken, ...base, 'role': role, ...bank.toJson()});
    await signedIn(j);
  });

  Widget _roleCard(String r, IconData icon, String title) {
    final on = role == r;
    return Expanded(
      child: Material(
        color: on ? const Color(0xFFFFF7E0) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: on ? C.amber : C.line, width: on ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy.isEmpty ? () => setState(() => role = r) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(spacing: 4, children: [
              Icon(icon, size: 22, color: on ? C.amberInk : C.navy),
              Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: on ? C.amberInk : C.text)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _select(String label, String value, String empty, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(R.ctl),
          onTap: busy.isEmpty ? onTap : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 9),
            decoration: BoxDecoration(border: Border.all(color: C.field), borderRadius: BorderRadius.circular(R.ctl)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.muted)),
                  Text(value.isEmpty ? empty : value,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: value.isEmpty ? C.subtle : C.text)),
                ]),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 18, color: C.muted),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final (title, text) = switch (role) {
      roleNtReg => ('Đăng ký nhà thầu', 'Đăng dự án, chụp nhật ký thi công, gửi báo cáo cho chủ nhà. Vua Thầu xác minh rồi cấp tài khoản.'),
      roleTeamReg => ('Đăng ký tổ đội', 'Chụp công trình đang xây, nhận tiền như cộng tác viên, giới thiệu tổ đội trên bản đồ.'),
      _ => (
          'Trở thành cộng tác viên',
          'Chụp ảnh công trình đang xây, mỗi căn được ${money(cfg.payFor(cfg.minPhotos))} – ${money(cfg.payFor(cfg.minPhotos + 1))}.'
        ),
    };
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          AuthTop(title: title, text: text),
          Lift(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Box(
                raised: true,
                padding: const EdgeInsets.all(20),
                gap: 16,
                children: sent.isNotEmpty
                    ? [
                        // nhà thầu đã gửi đăng ký: chờ xác minh
                        const Icon(Icons.verified_outlined, size: 44, color: C.ok),
                        const Text('Đã gửi đăng ký', textAlign: TextAlign.center, style: T.formHead),
                        Text(sent, textAlign: TextAlign.center, style: T.muted),
                        Btn('Về màn đăng nhập', kind: BtnKind.primary, onPressed: () => Navigator.of(context).maybePop()),
                      ]
                    : [
                        const Text('Bạn là', style: T.formHead),
                        Row(spacing: 8, children: [
                          _roleCard(roleCtvReg, Icons.photo_camera_outlined, 'Cộng tác viên'),
                          _roleCard(roleNtReg, Icons.engineering_outlined, 'Nhà thầu'),
                          _roleCard(roleTeamReg, Icons.groups_outlined, 'Tổ đội'),
                        ]),
                        if (g != null && pays)
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
                              TextButton(
                                onPressed: busy.isEmpty ? choose : null,
                                child: const Text('Đổi', style: TextStyle(color: C.text, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                              ),
                            ]),
                          ),
                        Field(label: 'Họ tên', controller: name, capitalization: TextCapitalization.words, autofill: const [AutofillHints.name], placeholder: 'Nguyễn Văn A'),
                        Field(
                          label: 'Số điện thoại',
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          placeholder: '0901234567',
                          hint: 'Lần sau mở app, nhập số này là vào.',
                        ),
                        if (firm) ...[
                          Field(
                            label: role == roleTeamReg ? 'Tên tổ đội / công ty' : 'Tên công ty',
                            controller: company,
                            capitalization: TextCapitalization.words,
                            placeholder: role == roleTeamReg ? 'Tổ đội anh Tâm' : 'Công ty TNHH Xây dựng ...',
                          ),
                          const Text('Hạng mục thực hiện', style: T.cap),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final c in _cats)
                              FilterChip(
                                label: Text(c),
                                selected: cats.contains(c),
                                showCheckmark: false,
                                selectedColor: C.blueBg,
                                labelStyle: TextStyle(fontWeight: FontWeight.w700, color: cats.contains(c) ? C.navy3 : C.text),
                                onSelected: busy.isEmpty ? (on) => setState(() => on ? cats.add(c) : cats.remove(c)) : null,
                              ),
                          ]),
                        ],
                        const Padding(padding: EdgeInsets.only(top: 6), child: Text('ĐỊA CHỈ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.muted, letterSpacing: .6))),
                        Row(spacing: 8, children: [
                          _select('Tỉnh / Thành phố', prov, 'Chọn tỉnh', chooseProv),
                          _select('Phường / Xã', ward, prov.isEmpty ? 'Chọn tỉnh trước' : 'Chọn phường', chooseWard),
                        ]),
                        Field(label: 'Số nhà, tên đường', controller: street, placeholder: 'VD: 12 Nguyễn Huệ'),
                        if (pays) ...[
                          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Tài khoản nhận tiền', style: T.secT)),
                          BankFields(c: bank),
                        ],
                        Btn(role == roleNtReg ? 'Gửi đăng ký nhà thầu' : 'Tạo tài khoản',
                            kind: BtnKind.primary, onPressed: submit, busy: busy == 'go', disabled: busy.isNotEmpty),
                      ],
              ),
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text.rich(
                TextSpan(
                  text: 'Đã có tài khoản? ',
                  children: [TextSpan(text: 'Đăng nhập', style: TextStyle(fontWeight: FontWeight.w600, color: C.text, decoration: TextDecoration.underline))],
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: C.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
