// Tài khoản (GET /me): tài khoản nhận tiền, đổi mật khẩu, quy tắc, xoá tài khoản, đăng xuất.
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
  String get path => '/me';

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
    if (j['user'] is Map) me.value = (j['user'] as Map).cast<String, dynamic>();
    if (j['todo'] is num) badge.value = (j['todo'] as num).toInt();
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

  Future<void> save(String what, String p, Map<String, String> body, [void Function(Json)? after]) async {
    setState(() => op = what);
    try {
      final j = await put(p, body);
      toast(msgsOf(j));
      after?.call(j);
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

  /// CH Play bắt buộc: CTV tự xoá tài khoản ngay trong app. Xong thì đăng xuất.
  Future<void> removeAccount(int owed) async {
    final ok = await confirm(context,
        title: 'Xoá vĩnh viễn tài khoản?', text: '${owed > 0 ? 'Bạn sẽ mất ${money(owed)} chưa được trả. ' : ''}Không khôi phục được.', ok: 'Xoá tài khoản');
    if (!ok) return;
    try {
      final j = await delete('/me');
      await setToken(null); // màn gốc tự về đăng nhập
      toast(msgsOf(j));
    } catch (e) {
      if (loggedIn()) toast(errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    return Column(children: [
      const VtAppBar(title: 'Tài khoản', sub: 'Cộng tác viên', back: true),
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
    final m = d['money'] as Map?;
    final hasOwed = m != null; // money chỉ có với CTV
    final owed = asInt(m?['owed']);
    final min = cfg.minPhotos;
    final hasBank = str(b['owner']).isNotEmpty;
    final rules = <(String, String)>[
      ('image', 'Mỗi căn nhà: $min ảnh đạt = ${money(cfg.payFor(min))}, từ ${min + 1} ảnh = ${money(cfg.payFor(min + 1))}. Dưới $min ảnh không gửi được.'),
      ('clock', 'Ảnh chụp trong 30 ngày, có giờ và vị trí, thấy rõ công trình đang xây.'),
      ('spark', 'AI kiểm tra từng ảnh ngay khi tải lên và báo lỗi để bạn sửa trước khi gửi.'),
      ('shield', 'Admin duyệt hồ sơ. Ảnh trùng hoặc nhà đã nộp sẽ bị từ chối.'),
      ('wallet', 'Kế toán chuyển khoản gộp khi bạn có từ ${cfg.payMin} hồ sơ đã duyệt.'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        // ---- hồ sơ cá nhân: thẻ nổi, ảnh đại diện tròn ----
        Box(raised: true, padding: const EdgeInsets.all(20), children: [
          Row(spacing: 16, children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(gradient: navyGradient, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(initials(str(user['name'])),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: C.amber, letterSpacing: 0.5)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                Text(str(user['name']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.4, height: 1.2)),
                Text(str(user['username']), style: T.muted.copyWith(fontSize: 14)),
                const Pill('Cộng tác viên', tone: 'done'),
              ]),
            ),
          ]),
          if (str(user['email']).isNotEmpty) ...[
            const Divider(height: 1, color: C.line),
            Row(spacing: 8, children: [
              const Ic('user', color: C.muted, size: 16),
              Expanded(child: Text('Google: ${str(user['email'])}', style: T.muted)),
            ]),
          ],
        ]),

        // ---- thanh toán ----
        const _Group('Thanh toán'),
        _fold('bank', 'bank', 'Tài khoản nhận tiền',
            hasBank ? '${str(b['name'])} · ${str(b['no'])}' : (str(user['bank']).isNotEmpty ? 'Cần nhập lại theo 3 ô' : 'Chưa có, bấm để thêm'), [
          if (!hasBank && str(user['bank']).isNotEmpty)
            Text('Đang lưu: “${str(user['bank'])}”. Nhập lại theo 3 ô dưới để kế toán chuyển nhanh, đúng.', style: T.muted.copyWith(color: C.alert)),
          BankFields(c: bank!),
          Btn('Lưu tài khoản', kind: BtnKind.primary, busy: op == 'bank', onPressed: () => save('bank', '/me/bank', bank!.toJson())),
        ], warn: !hasBank),

        // ---- bảo mật ----
        const _Group('Đăng nhập và bảo mật'),
        _fold('pw', 'lock', 'Đổi mật khẩu', 'Ít nhất 6 ký tự', [
          Field(label: 'Mật khẩu hiện tại', controller: pwOld, obscure: true, autofill: const [AutofillHints.password]),
          Field(label: 'Mật khẩu mới', controller: pwNew, obscure: true, autofill: const [AutofillHints.newPassword], hint: 'Ít nhất 6 ký tự.'),
          Btn('Đổi mật khẩu',
              kind: BtnKind.primary,
              busy: op == 'pw',
              disabled: pwOld.text.isEmpty || pwNew.text.length < 6,
              onPressed: () => save('pw', '/me/password', {'old': pwOld.text, 'new': pwNew.text}, (j) {
                    // token cũ hết hiệu lực: dùng token mới máy chủ trả
                    if (j['access_token'] is String) setToken(j['access_token'] as String);
                    pwOld.clear();
                    pwNew.clear();
                  })),
        ]),
        if (hasOwed)
          _fold('del', 'trash', 'Xoá tài khoản', 'Xoá vĩnh viễn, không khôi phục được', [
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

        // ---- hỗ trợ ----
        const _Group('Hỗ trợ'),
        _fold('rules', 'book', 'Quy tắc nghiệm thu', 'Ảnh đạt, tiền hồ sơ, thanh toán', [
          for (final (ic, t) in rules)
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: C.blueBg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Ic(ic, color: C.navy3, size: 16),
              ),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 5), child: Text(t, style: const TextStyle(color: C.text, fontSize: 14, height: 1.45)))),
            ]),
        ]),

        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: logout,
            borderRadius: BorderRadius.circular(R.ctl),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Đăng xuất', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text, decoration: TextDecoration.underline)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('VUA THẦU MAP${version.isNotEmpty ? ' · PHIÊN BẢN $version' : ''}', style: T.cap.copyWith(color: C.subtle, letterSpacing: 0.6)),
      ],
    );
  }

  /// 1 dòng cài đặt kiểu Airbnb: biểu tượng, tiêu đề + mô tả, mũi tên; bấm để mở nội dung ngay bên dưới.
  Widget _fold(String id, String icon, String title, String sub, List<Widget> children, {bool warn = false}) {
    final on = open == id;
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          expanded: on,
          button: true,
          child: InkWell(
            onTap: () => setState(() => open = on ? '' : id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(spacing: 14, children: [
                Ic(icon, color: C.text, size: 22),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(title, style: const TextStyle(fontSize: 16, color: C.text)),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.muted.copyWith(color: warn ? C.wait : C.muted)),
                  ]),
                ),
                AnimatedRotation(turns: on ? 0.25 : 0, duration: const Duration(milliseconds: 150), child: const Ic('right', color: C.text, size: 18)),
              ]),
            ),
          ),
        ),
        if (on) Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: children)),
      ]),
    );
  }
}

/// Tên nhóm cài đặt: chữ 20px đậm.
class _Group extends StatelessWidget {
  const _Group(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 32, bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: C.text, letterSpacing: -0.3)),
      );
}
