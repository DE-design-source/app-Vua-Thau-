// "Logo trên ảnh" (thiết kế 24/11/2026): xem trước dải chữ in trên ảnh nhật ký; logo đang dùng (mặc định: tên công ty
// dạng chữ); Tải logo công ty lên (PNG nền trong, tối thiểu 300×300px) HOẶC nhập tên thương hiệu (tối đa 20 ký tự);
// Kích thước; Giữ nhãn "Vua Thầu xác minh"; Lưu thay đổi.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../stamp.dart';
import '../toast.dart';
import '../ui.dart';
import 'nt.dart' show NtBranding, loadBranding, ntBranding, ntCompany, ntProfile;

const _ink = Color(0xFF0B2340), _gold = Color(0xFFFFB81C), _blue = Color(0xFF0A4BB5), _slate = Color(0xFF64748B);

class NtLogoScreen extends StatefulWidget {
  const NtLogoScreen({super.key});
  @override
  State<NtLogoScreen> createState() => _NtLogoScreenState();
}

class _NtLogoScreenState extends State<NtLogoScreen> {
  late final NtBranding b0 = ntBranding.value;
  late final brand = TextEditingController(text: b0.brand);
  late double size = b0.size.toDouble();
  late bool badge = b0.badge;
  bool saving = false, uploading = false;

  @override
  void initState() {
    super.initState();
    brand.addListener(() => setState(() {}));
    ntBranding.addListener(_tick);
  }

  void _tick() => setState(() {});

  @override
  void dispose() {
    ntBranding.removeListener(_tick);
    brand.dispose();
    super.dispose();
  }

  String get shownBrand => brand.text.trim().isNotEmpty ? brand.text.trim() : ntCompany.value;

  Future<void> pickLogo() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      setState(() => uploading = true);
      final name = x.name.toLowerCase();
      final j = await upload('/nt/logo', [UpFile('file', x.path, x.name, name.endsWith('.png') ? 'image/png' : 'image/jpeg')]);
      final p = (j['profile'] as Map?)?.cast<String, dynamic>();
      if (p != null) {
        ntProfile.value = p;
        await loadBranding(p, force: true);
      }
      toast(str(j['message']).isNotEmpty ? str(j['message']) : 'Đã tải logo lên.');
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> removeLogo() async {
    setState(() => uploading = true);
    try {
      final j = await delete('/nt/logo');
      final p = (j['profile'] as Map?)?.cast<String, dynamic>();
      if (p != null) {
        ntProfile.value = p;
        await loadBranding(p, force: true);
      }
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final j = await put('/nt/branding', {'brand': brand.text.trim(), 'size': size.round(), 'badge': badge});
      final p = (j['profile'] as Map?)?.cast<String, dynamic>();
      if (p != null) {
        ntProfile.value = p;
        await loadBranding(p);
      }
      toast(str(j['message']).isNotEmpty ? str(j['message']) : 'Đã lưu.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  @override
  Widget build(BuildContext context) {
    final b = ntBranding.value;
    final scale = const {1: 0.8, 2: 1.0, 3: 1.25}[size.round()] ?? 1.0;
    final sizeLabel = const {1: 'Nhỏ', 2: 'Vừa', 3: 'Lớn'}[size.round()] ?? 'Vừa';
    final sample = StampData(DateTime.now(), const Pos(10.782714, 106.719365, 8), '23 Trần Bạch Đằng, P. An Khánh, TP. HCM',
        brand: shownBrand, logo: b.logo, scale: scale, badge: badge);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        title: const Text('Logo trên ảnh', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        const Text('XEM TRƯỚC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: Color(0xFF94A3B8))),
        const SizedBox(height: 6),
        // ảnh mẫu: nền trời + công trình (vẽ), dải chữ in đúng như khi chụp
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(fit: StackFit.expand, children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF8DB4DE), Color(0xFFC9D9EA), Color(0xFF7A7F86), Color(0xFF4B4F55)],
                    stops: [0, .45, .46, 1],
                  ),
                ),
              ),
              CustomPaint(painter: StampPainter(sample)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _card([
          Row(spacing: 12, children: [
            Container(
              width: 72,
              height: 44,
              padding: const EdgeInsets.all(4),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(8)),
              child: b.logo != null
                  ? RawImage(image: b.logo, fit: BoxFit.contain)
                  : FittedBox(child: Text(shownBrand.isEmpty ? 'Logo' : shownBrand, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Logo đang dùng', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                Text(b.hasLogo ? 'Logo công ty đã tải lên' : 'Mặc định: tên công ty dạng chữ', style: const TextStyle(fontSize: 12, color: _slate)),
              ]),
            ),
            if (b.hasLogo) TextButton(onPressed: uploading ? null : removeLogo, child: const Text('Bỏ logo')),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: uploading ? null : pickLogo,
              icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload),
              label: Text(b.hasLogo ? 'Đổi logo công ty' : 'Tải logo công ty lên', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 6),
          const Text('PNG nền trong, tối thiểu 300×300px', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(spacing: 8, children: [
              Expanded(child: Divider()),
              Text('HOẶC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
              Expanded(child: Divider()),
            ]),
          ),
          const Text('Nhập tên thương hiệu tại đây', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          TextField(
            controller: brand,
            maxLength: 20,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: ntCompany.value.isNotEmpty ? ntCompany.value : 'Smartcons',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              helperText: b.hasLogo ? 'Đang dùng logo: tên này dùng khi bỏ logo' : 'Hiện dạng chữ trên ảnh khi chưa có logo',
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _card([
          Row(children: [
            const Expanded(child: Text('Kích thước', style: TextStyle(fontWeight: FontWeight.w800, color: _ink))),
            Text(sizeLabel, style: const TextStyle(color: _slate, fontWeight: FontWeight.w700)),
          ]),
          Slider(value: size, min: 1, max: 3, divisions: 2, activeColor: _blue, label: sizeLabel, onChanged: (v) => setState(() => size = v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: badge,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF16A34A),
            onChanged: (v) => setState(() => badge = v),
            title: const Text('Giữ nhãn "Vua Thầu xác minh"', style: TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 14)),
            subtitle: const Text('Chủ nhà tin ảnh hơn khi thấy nhãn này', style: TextStyle(fontSize: 12, color: _slate)),
          ),
        ]),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : save,
              child: Text(saving ? 'Đang lưu…' : 'Lưu thay đổi', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}
