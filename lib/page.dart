// Dữ liệu 1 trang: tải khi mở, tải lại mỗi lần quay về màn (như usePage + useFocusEffect của bản Expo).
import 'package:flutter/material.dart';

import 'api.dart';
import 'toast.dart';

final routeObserver = RouteObserver<ModalRoute<void>>();

abstract interface class Reloadable {
  Future<void> load();
}

mixin PageData<W extends StatefulWidget> on State<W> implements Reloadable, RouteAware {
  Json? d;
  String err = '';
  bool busy = false;

  String get path;

  /// Màn trong tab: thanh tab tự gọi load() khi chọn tab / quay về, không tự nghe route.
  bool get watchRoute => true;

  void onData(Json j) {}

  @override
  Future<void> load() async {
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final j = await api(path);
      toast(msgsOf(j));
      if (!mounted) return;
      setState(() {
        d = j;
        err = '';
      });
      onData(j);
    } catch (e) {
      if (mounted) setState(() => err = errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  bool _sub = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ModalRoute.of(context);
    if (watchRoute && !_sub && r != null) {
      routeObserver.subscribe(this, r);
      _sub = true;
    }
  }

  @override
  void dispose() {
    if (_sub) routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => load();
  @override
  void didPush() {}
  @override
  void didPop() {}
  @override
  void didPushNext() {}
}
