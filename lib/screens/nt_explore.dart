// "Khám phá" (thiết kế "App – Khám phá" 24/11/2026): bảng tin thi công gần đây của các nhà thầu trên Vua Thầu.
// Tìm theo công ty / dự án / địa chỉ; chip lọc Tất cả · Gần tôi · Đã xác minh · Tổng thầu · Thầu phụ · Tổ đội.
// Mỗi thẻ: công ty (tích xác minh), loại hình, bao lâu trước, khoảng cách, dự án + địa chỉ, ảnh mới nhất (tối đa 4),
// nút Xem hồ sơ (link hồ sơ năng lực công khai), Gọi, Zalo. Nút "Bản đồ" chuyển sang bản đồ dự án của mình.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../toast.dart';
import '../ui.dart';
import '../zalo.dart';

const _ink = Color(0xFF0B2340), _gold = Color(0xFFFFB81C), _blue = Color(0xFF0A4BB5), _slate = Color(0xFF64748B), _bg = Color(0xFFF4F6FA);

const _filters = [('all', 'Tất cả'), ('near', 'Gần tôi'), ('verified', 'Đã xác minh'), ('tong_thau', 'Tổng thầu'), ('thau_phu', 'Thầu phụ'), ('to_doi', 'Tổ đội')];

class NtExplore extends StatefulWidget {
  /// map: bản đồ dự án của nhà thầu (nút chuyển Danh sách / Bản đồ).
  const NtExplore({super.key, required this.map});
  final Widget map;
  @override
  State<NtExplore> createState() => NtExploreState();
}

class NtExploreState extends State<NtExplore> {
  final q = TextEditingController();
  String filter = 'all', err = '';
  bool loading = false, onMap = false;
  List<Json> items = const [];
  Position? pos;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    q.dispose();
    super.dispose();
  }

  /// Vị trí hiện tại (chỉ khi đã cho phép; Gần tôi thì hỏi quyền).
  Future<Position?> _locate({bool ask = false}) async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)));
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = '';
    });
    try {
      pos ??= await _locate(ask: filter == 'near');
      if (filter == 'near' && pos == null) throw ApiError('Bật quyền vị trí để xem nhà thầu gần bạn.');
      final qs = <String, String>{
        if (q.text.trim().isNotEmpty) 'q': q.text.trim(),
        if (filter != 'all') 'filter': filter,
        if (pos != null) 'lat': '${pos!.latitude}',
        if (pos != null) 'lng': '${pos!.longitude}',
      };
      final j = await api(Uri(path: '/nt/explore', queryParameters: qs.isEmpty ? null : qs).toString());
      if (mounted) setState(() => items = ((j['items'] as List?) ?? const []).cast<Json>());
    } catch (e) {
      if (mounted) setState(() => err = errMsg(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _search(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), load);
  }

  String _ago(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 60) return '${m < 1 ? 1 : m} phút trước';
    if (m < 60 * 24) return '${m ~/ 60} giờ trước';
    final d = m ~/ (60 * 24);
    return d == 1 ? 'Hôm qua' : '$d ngày trước';
  }

  Widget _header(BuildContext context) => Container(
        color: _ink,
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Row(children: [
            const Expanded(child: Text('Khám phá', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
            // Danh sách / Bản đồ
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(999)),
              child: Row(children: [
                for (final (m, label, icon) in [(false, 'Tin mới', Icons.view_agenda_outlined), (true, 'Bản đồ', Icons.map_outlined)])
                  GestureDetector(
                    onTap: () => setState(() => onMap = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: onMap == m ? _gold : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                      child: Row(spacing: 4, children: [
                        Icon(icon, size: 15, color: onMap == m ? _ink : Colors.white),
                        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: onMap == m ? _ink : Colors.white)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ]),
          if (!onMap) ...[
            TextField(
              controller: q,
              onChanged: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => load(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Tìm nhà thầu, dự án, khu vực…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          q.clear();
                          load();
                        }),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            SizedBox(
              height: 32,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final (k, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: filter == k,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide.none,
                      backgroundColor: Colors.white12,
                      selectedColor: _gold,
                      labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: filter == k ? _ink : Colors.white),
                      onSelected: (_) {
                        setState(() => filter = k);
                        load();
                      },
                    ),
                  ),
              ]),
            ),
          ],
        ]),
      );

  Widget _photos(Json it) {
    final ph = ((it['photos'] as List?) ?? const []).cast<String>();
    if (ph.isEmpty) return const SizedBox.shrink();
    final more = asInt(it['photo_count']) - ph.length;
    Widget img(int i) => Stack(fit: StackFit.expand, children: [
          Image.network('$host${ph[i]}?size=small', fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: const Color(0xFFE3E8F0))),
          if (i == ph.length - 1 && more > 0)
            Container(color: Colors.black45, alignment: Alignment.center, child: Text('+$more', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
        ]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 170,
        child: ph.length == 1
            ? img(0)
            : Row(spacing: 3, children: [
                Expanded(flex: 2, child: img(0)),
                Expanded(child: Column(spacing: 3, children: [for (var i = 1; i < ph.length; i++) Expanded(child: img(i))])),
              ]),
      ),
    );
  }

  Widget _card(Json it) {
    final company = str(it['company']);
    final dist = it['distance_km'] as num?;
    final tags = [str(it['kind']), str(it['role'])].where((s) => s.isNotEmpty).join(' · ');
    final phone = str(it['phone']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Row(spacing: 10, children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _ink,
            child: Text(initials(company), style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(spacing: 4, children: [
                Flexible(child: Text(company, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 14.5))),
                if (it['verified'] == true) const Icon(Icons.verified, size: 16, color: _blue),
              ]),
              Text(
                [if (tags.isNotEmpty) tags, _ago(str(it['taken_at'])), if (dist != null) '${dist < 1 ? '<1' : dist.toStringAsFixed(dist < 10 ? 1 : 0)} km'].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _slate),
              ),
            ]),
          ),
          if (it['mine'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFFFF7E0), borderRadius: BorderRadius.circular(999)),
              child: const Text('Của bạn', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
            ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text(str(it['project']), style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
          if (str(it['address']).isNotEmpty)
            Row(spacing: 3, children: [
              const Icon(Icons.place_outlined, size: 14, color: _slate),
              Expanded(child: Text(str(it['address']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _slate))),
            ]),
          if (str(it['note']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(str(it['note']), maxLines: 3, overflow: TextOverflow.ellipsis)),
        ]),
        _photos(it),
        Row(spacing: 8, children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => launchUrl(Uri.parse('$host${str(it['portfolio'])}'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('Xem hồ sơ', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          if (phone.isNotEmpty && it['mine'] != true) ...[
            IconButton.outlined(tooltip: 'Gọi', onPressed: () => launchUrl(Uri.parse('tel:$phone')), icon: const Icon(Icons.call_outlined, color: _blue)),
            IconButton.outlined(
              tooltip: 'Zalo',
              onPressed: () async {
                if (!await openZaloChat(phone)) toast('Không mở được Zalo.');
              },
              icon: const Text('Zalo', style: TextStyle(fontWeight: FontWeight.w900, color: _blue, fontSize: 12)),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _feed() {
    if (loading && items.isEmpty) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(err, style: const TextStyle(color: C.bad))),
          if (items.isEmpty && err.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Column(spacing: 8, children: [
                Icon(Icons.travel_explore, size: 48, color: Color(0xFF94A3B8)),
                Text('Chưa có hoạt động thi công phù hợp', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                Text('Thử bỏ bớt bộ lọc hoặc tìm từ khoá khác.', textAlign: TextAlign.center, style: TextStyle(color: _slate)),
              ]),
            ),
          for (final it in items) _card(it),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: _bg,
        child: Column(children: [
          _header(context),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(index: onMap ? 1 : 0, children: [_feed(), widget.map]),
            ),
          ),
        ]),
      );
}
