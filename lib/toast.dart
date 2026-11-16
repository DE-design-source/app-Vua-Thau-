// Thông báo ngắn ở đầu màn hình (thay cho thông báo flash của web). Gọi toast() ở đâu cũng được.
import 'dart:async';

import 'package:flutter/material.dart';

final _msgs = ValueNotifier<List<String>>(const []);
Timer? _timer;

/// Nhận 1 chuỗi, 1 danh sách chuỗi hoặc null.
void toast(Object? m) {
  final list = (m is List ? m : [m]).where((e) => e != null && '$e'.isNotEmpty).map((e) => '$e').toList();
  if (list.isEmpty) return;
  _msgs.value = list;
  _timer?.cancel();
  _timer = Timer(Duration(milliseconds: 3500 + 1500 * list.length), () => _msgs.value = const []);
}

/// Bọc toàn app (MaterialApp.builder), vẽ thông báo nổi trên mọi màn.
class ToastHost extends StatelessWidget {
  const ToastHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      ValueListenableBuilder<List<String>>(
        valueListenable: _msgs,
        builder: (context, msgs, _) {
          if (msgs.isEmpty) return const SizedBox.shrink();
          return Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: Semantics(
              liveRegion: true,
              child: Material(
                color: const Color(0xFF101828),
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _msgs.value = const [],
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 4,
                      children: [
                        for (final m in msgs) Text(m, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
