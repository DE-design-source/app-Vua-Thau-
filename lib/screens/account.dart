// Tài khoản (như /toi): tài khoản nhận tiền, đổi mật khẩu, quy tắc, xoá tài khoản, đăng xuất.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../auth.dart';
import '../page.dart';
import '../toast.dart';
import '../ui.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with PageData {
  @override
  String get path => '/toi';
  @override
  bool get watchRoute => false;

  BankCtl? bank;
  final pwOld = TextEditingController(), pwNew = TextEditingController();
  String open = '';
  String op = '';
  String version = '';
  bool _first = true;

  @override
  void initState() {
    super.initState();
    pwOld.addListener(() => setState(() {}));
    pwNew.addListener(() => setState(() {}));
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => version = p.version);
    }, onError: (_) {});
  }

  @override
  void onData(Json j) {
    if (!_first) return; // giữ những gì CTV đang gõ dở khi tải lại
    _first = false;
    final b = (j['bank'] as Map?) ?? const {};
    final has = str(b['owner']).isNotEmpty;
    setState(() {
      bank = has ? BankCtl(name: str(b['name']), no: str(b['no']), owner: str(b['owner'])) : BankCtl();
      open = has ? '' : 'bank';
    });
  }

  @override
  void dispose() {
    bank?.dispose();
    pwOld.dispose();
    pwNew.dispose();
    super.dispose();
  }

  Future<void> post(String what, String p, Map<String, String> body, [VoidCallback? after]) async {
    setState(() => op = what);
    try {
      final j = await api(p, body);
      toast(msgsOf(j));
      after?.call();
      load();
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => op = '');
    }
  }

  Future<void> logout() async {
    if (await confirm(context, title: 'Đăng xuất?', text: 'Bạn cần nhập lại số điện thoại và mật khẩu để vào app.', ok: 'Đăng xuất')) {
      await setToken(null); // màn gốc tự về đăng nhập
    }
  }

  /// CH Play bắt buộc: CTV tự xoá tài khoản ngay trong app. Xong thì máy chủ trả url /login, app tự đăng xuất.
  Future<void> removeAccount(int owed) async {
    final ok = await confirm(context,
        title: 'Xoá vĩnh viễn tài khoản?', text: '${owed > 0 ? 'Bạn sẽ mất ${money(owed)} chưa được trả. ' : ''}Không khôi phục được.', ok: 'Xoá tài khoản');
    if (!ok) return;
    try {
      await api('/toi/xoa', {});
    } catch (e) {
      if (loggedIn()) toast(errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    return Column(children: [
      const VtAppBar(title: 'Tài khoản', sub: 'Cộng tác viên'),
      Expanded(
        child: d == null || bank == null
            ? ListView(children: [
                Loading(err: err, retry: load),
                // Không tải được (mất mạng, máy chủ lỗi...): vẫn đăng xuất được, không bao giờ kẹt
                if (err.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Btn('Đăng xuất', icon: 'logout', kind: BtnKind.danger, onPressed: logout)),
              ])
            : _body(d),
      ),
    ]);
  }

  Widget _body(Json d) {
    final user = (d['user'] as Map?) ?? const {};
    final b = (d['bank'] as Map?) ?? const {};
    final hasOwed = d.containsKey('owed') && d['owed'] != null;
    final owed = asInt(d['owed']);
    final min = cfg.minPhotos;
    final rules = <(String, String)>[
      ('image', 'Mỗi căn nhà: $min ảnh đạt = ${money(cfg.payFor(min))}, từ ${min + 1} ảnh = ${money(cfg.payFor(min + 1))}. Dưới $min ảnh không gửi được.'),
      ('clock', 'Ảnh chụp trong 30 ngày, có giờ và vị trí, thấy rõ công trình đang xây.'),
      ('spark', 'AI kiểm tra từng ảnh ngay khi tải lên và báo lỗi để bạn sửa trước khi gửi.'),
      ('shield', 'Admin duyệt hồ sơ. Ảnh trùng hoặc nhà đã nộp sẽ bị từ chối.'),
      ('wallet', 'Kế toán chuyển khoản gộp khi bạn có từ ${cfg.payMin} hồ sơ đã duyệt.'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Box(children: [
          Row(spacing: 14, children: [
            Avatar(size: 56, child: Text(initials(str(user['name'])), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.navy3))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(user['name']), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: C.text)),
                Text('${str(user['phone'])} · Cộng tác viên', style: T.muted),
                if (str(user['email']).isNotEmpty) Text('Google: ${str(user['email'])}', style: T.muted),
              ]),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        _fold('bank', 'bank', 'Tài khoản nhận tiền', [
          if (str(b['owner']).isEmpty && str(user['bank']).isNotEmpty)
            Text('Đang lưu: “${str(user['bank'])}”. Nhập lại theo 3 ô dưới để kế toán chuyển nhanh, đúng.', style: T.muted.copyWith(color: C.warn)),
          BankFields(c: bank!),
          Btn('Lưu tài khoản', kind: BtnKind.dark, busy: op == 'bank', onPressed: () => post('bank', '/toi/ngan-hang', bank!.toForm())),
        ]),
        const SizedBox(height: 12),
        _fold('pw', 'lock', 'Đổi mật khẩu', [
          Field(label: 'Mật khẩu hiện tại', controller: pwOld, obscure: true, autofill: const [AutofillHints.password]),
          Field(label: 'Mật khẩu mới', controller: pwNew, obscure: true, autofill: const [AutofillHints.newPassword], hint: 'Ít nhất 6 ký tự.'),
          Btn('Đổi mật khẩu',
              kind: BtnKind.dark,
              busy: op == 'pw',
              disabled: pwOld.text.isEmpty || pwNew.text.length < 6,
              onPressed: () => post('pw', '/toi/mat-khau', {'old': pwOld.text, 'new': pwNew.text}, () {
                    pwOld.clear();
                    pwNew.clear();
                  })),
        ]),
        const SizedBox(height: 12),
        _fold('rules', 'book', 'Quy tắc nghiệm thu', [
          for (final (ic, t) in rules)
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              Ic(ic, color: C.navy3),
              Expanded(child: Text(t, style: const TextStyle(color: C.text, height: 1.4))),
            ]),
        ]),
        // máy chủ bản cũ (chưa có /toi/xoa) không gửi owed: ẩn mục này để không bấm ra lỗi
        if (hasOwed) ...[
          const SizedBox(height: 12),
          _fold('del', 'trash', 'Xoá tài khoản', [
            const Text(
              'Xoá họ tên, số điện thoại, email, tài khoản ngân hàng; không đăng nhập lại được. '
              'Hồ sơ đã nộp và tiền đã trả được giữ dưới tên ẩn danh để kế toán đối soát.',
              style: TextStyle(color: C.text, height: 1.4),
            ),
            if (owed > 0)
              Text('Bạn còn ${money(owed)} chưa được trả. Xoá tài khoản thì kế toán không chuyển được số tiền này.',
                  style: const TextStyle(color: C.bad, fontWeight: FontWeight.w600, height: 1.4)),
            Btn('Xoá vĩnh viễn tài khoản', icon: 'trash', kind: BtnKind.danger, onPressed: () => removeAccount(owed)),
          ]),
        ],
        const SizedBox(height: 12),
        Btn('Đăng xuất', icon: 'logout', kind: BtnKind.danger, onPressed: logout),
        const SizedBox(height: 12),
        Text('Vua Thầu Nghiệm thu${version.isNotEmpty ? ' · bản $version' : ''}', textAlign: TextAlign.center, style: T.muted),
      ],
    );
  }

  Widget _fold(String id, String icon, String title, List<Widget> children) {
    final on = open == id;
    return Box(children: [
      Semantics(
        expanded: on,
        button: true,
        child: InkWell(
          onTap: () => setState(() => open = on ? '' : id),
          child: Row(spacing: 10, children: [
            Ic(icon, color: C.navy3),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text))),
            AnimatedRotation(turns: on ? 0.25 : 0, duration: const Duration(milliseconds: 150), child: const Ic('right', color: C.muted, size: 18)),
          ]),
        ),
      ),
      if (on) ...children,
    ]);
  }
}
