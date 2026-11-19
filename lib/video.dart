// Video công trình: CTV quay / chọn video, xem lại. Admin xem thêm (không qua AI); hồ sơ có video được cộng thưởng.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'lfile.dart';
import 'picker.dart';
import 'toast.dart';
import 'ui.dart';

const maxVideos = 5;
const videoLimit = 200 * 1024 * 1024;

/// Link xem video (máy chủ trả đường dẫn có chữ ký, không cần token).
Uri videoUri(Json v) => Uri.parse(host).resolve(str(v['src']));

String mb(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB' : '${(bytes / 1024).ceil()} KB';

String videoMime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.mov')) return 'video/quicktime';
  if (n.endsWith('.webm')) return 'video/webm';
  if (n.endsWith('.3gp')) return 'video/3gpp';
  if (n.endsWith('.mkv')) return 'video/x-matroska';
  return 'video/mp4';
}

/// Mục "Video công trình" trong chi tiết hồ sơ: lưới video, quay / chọn thêm khi còn sửa được.
class VideoSection extends StatefulWidget {
  const VideoSection({super.key, required this.hid, required this.videos, required this.editable, required this.onChanged});
  final int hid;
  final List<Json> videos;
  final bool editable;
  final VoidCallback onChanged;
  @override
  State<VideoSection> createState() => _VideoSectionState();
}

class _VideoSectionState extends State<VideoSection> {
  double? pct;
  String err = '';

  int get room => maxVideos - widget.videos.length;

  Future<void> add(ImageSource src) async {
    XFile? x;
    try {
      x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(minutes: 3));
    } catch (e) {
      toast(src == ImageSource.camera ? 'Không mở được camera quay video: $e' : 'Không mở được thư viện video: $e');
      return;
    }
    if (x == null) return;
    if (await localLength(x.path) > videoLimit) {
      setState(() => err = 'Video quá 200 MB, quay ngắn lại rồi thử lại.');
      return;
    }
    final name = x.name.isNotEmpty ? x.name : 'video.mp4';
    setState(() {
      err = '';
      pct = 0;
    });
    try {
      final j = await upload('/houses/${widget.hid}/videos', [UpFile('files', x.path, name, videoMime(name))], onProgress: (p) {
        if (mounted) setState(() => pct = p);
      });
      toast(msgsOf(j));
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => err = errMsg(e));
    } finally {
      if (mounted) setState(() => pct = null);
    }
  }

  Future<void> del(Json v) async {
    final ok = await confirm(context, title: 'Xoá video này?', ok: 'Xoá');
    if (!ok) return;
    try {
      final j = await delete('/houses/${widget.hid}/videos/${asInt(v['id'])}');
      toast(str(j['message']).isNotEmpty ? str(j['message']) : 'Đã xoá video.');
      widget.onChanged();
    } catch (e) {
      toast(errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = widget.videos;
    final busy = pct != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Sec('Video công trình · ${vs.length}', right: 'tối đa $maxVideos'),
      if (vs.isNotEmpty)
        PhotoGrid(children: [
          for (var k = 0; k < vs.length; k++)
            Stack(fit: StackFit.expand, children: [
              VideoTile(v: vs[k], index: k + 1, onTap: () => push(context, VideoScreen(videos: vs, at: k))),
              if (widget.editable) DelBtn(icon: 'trash', label: 'Xoá video ${k + 1}', onTap: busy ? null : () => del(vs[k])),
            ]),
        ]),
      if (widget.editable && room > 0) ...[
        Row(spacing: 8, children: [
          Expanded(child: Btn('Quay video', icon: 'video', kind: BtnKind.dark, onPressed: busy ? null : () => add(ImageSource.camera))),
          Expanded(child: Btn('Chọn video', icon: 'upload', onPressed: busy ? null : () => add(ImageSource.gallery))),
        ]),
        Text(
            'Quay 1 vòng quanh công trình, tối đa 3 phút. Video không tính vào số ảnh đạt${cfg.videoBonus > 0 ? ', nhưng hồ sơ có video được cộng thêm ${money(cfg.videoBonus)}' : ''}.',
            style: T.hint),
      ],
      if (!widget.editable && vs.isEmpty) Text('Chưa có video.', style: T.muted),
      if (pct != null) Progress(pct: pct!, doneText: 'Đã tải xong, đang lưu video…'),
      if (err.isNotEmpty) Text(err, style: const TextStyle(color: C.bad, fontSize: 14)),
    ]);
  }
}

/// Ô video trong lưới: nền tối, nút phát tròn, dung lượng.
class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.v, required this.index, required this.onTap});
  final Json v;
  final int index;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Xem video $index',
        child: Material(
          color: C.navy,
          child: InkWell(
            onTap: onTap,
            child: Stack(fit: StackFit.expand, children: [
              const DecoratedBox(decoration: BoxDecoration(gradient: navyGradient)),
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: cardShadow),
                  alignment: Alignment.center,
                  child: const Padding(padding: EdgeInsets.only(left: 3), child: Ic('play', color: C.text, size: 20)),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Text('$index · ${mb(asInt(v['size']))}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      );
}

/// Xem video toàn màn hình, vuốt ngang sang video khác.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.videos, required this.at});
  final List<Json> videos;
  final int at;
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final PageController page = PageController(initialPage: widget.at);
  late int at = widget.at;

  @override
  void dispose() {
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            PageView.builder(
              controller: page,
              itemCount: widget.videos.length,
              onPageChanged: (i) => setState(() => at = i),
              itemBuilder: (context, i) => _Player(uri: videoUri(widget.videos[i]), active: i == at),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                tooltip: 'Đóng',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Ic('x', color: Colors.white, size: 22),
              ),
            ),
            if (widget.videos.length > 1)
              Positioned(
                top: 20,
                right: 16,
                child: Text('${at + 1}/${widget.videos.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
              ),
          ]),
        ),
      );
}

class _Player extends StatefulWidget {
  const _Player({required this.uri, required this.active});
  final Uri uri;
  final bool active;
  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  late final VideoPlayerController c = VideoPlayerController.networkUrl(widget.uri);
  String err = '';

  @override
  void initState() {
    super.initState();
    c.addListener(_tick);
    c.initialize().then((_) {
      if (mounted && widget.active) c.play();
    }).catchError((Object e) {
      if (mounted) setState(() => err = 'Không phát được video. Kiểm tra mạng hoặc tải lại trang hồ sơ.');
    });
  }

  @override
  void didUpdateWidget(_Player old) {
    super.didUpdateWidget(old);
    if (!widget.active && c.value.isPlaying) c.pause();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_tick);
    c.dispose();
    super.dispose();
  }

  static String _t(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (err.isNotEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(err, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))));
    }
    final v = c.value;
    if (!v.isInitialized) return const Center(child: CircularProgressIndicator(color: Colors.white));
    return Column(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => v.isPlaying ? c.pause() : c.play(),
          child: Stack(alignment: Alignment.center, children: [
            Center(child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(c))),
            if (!v.isPlaying)
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Padding(padding: EdgeInsets.only(left: 4), child: Ic('play', color: Colors.white, size: 28)),
              ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(spacing: 12, children: [
          Text(_t(v.position), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
          Expanded(
            child: VideoProgressIndicator(c,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 10),
                colors: const VideoProgressColors(playedColor: C.amber, bufferedColor: Colors.white38, backgroundColor: Colors.white12)),
          ),
          Text(_t(v.duration), style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      ),
    ]);
  }
}
