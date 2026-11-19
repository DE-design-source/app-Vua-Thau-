// Trợ lý khung ngắm: app Android quét chữ + cảm biến; bản web (PWA iPhone) không có.
export 'live_io.dart' if (dart.library.js_interop) 'live_web.dart';
export 'scan_text.dart';
