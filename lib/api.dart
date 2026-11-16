// Nói chuyện với máy chủ nghiemthu.vuathau.com.vn. App gọi đúng các route của web, gửi header X-App: 1:
// GET trả dữ liệu trang dạng JSON, POST trả {url, msgs, token}. Luật kiểm ảnh, luật tiền, AI, Drive đều nằm ở máy chủ.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'toast.dart';

/// Đổi máy chủ khi build: flutter build apk --dart-define=API_URL=https://...
const base = String.fromEnvironment('API_URL', defaultValue: 'https://nghiemthu.vuathau.com.vn');

typedef Json = Map<String, dynamic>;

/// Cấu hình chung lấy từ máy chủ (/app.json): trạng thái, luật tiền, giai đoạn, ngân hàng...
class Cfg {
  Cfg.fromJson(Json j)
      : status = (j['STATUS'] as Map).map((k, v) => MapEntry('$k', (v as List).map((e) => '$e').toList())),
        payMin = (j['PAY_MIN'] as num).toInt(),
        minPhotos = (j['MIN_PHOTOS'] as num).toInt(),
        maxPhotos = (j['MAX_PHOTOS'] as num).toInt(),
        stages = (j['STAGES'] as List).map((e) => '$e').toList(),
        banks = (j['BANKS'] as List).map((e) => '$e').toList(),
        pay = (j['PAY'] as List).map((e) => (e as num).toInt()).toList(),
        google = '${j['GOOGLE'] ?? ''}';

  /// mã: [nhãn nội bộ, nhãn cho CTV, tông màu]
  final Map<String, List<String>> status;
  final int payMin, minPhotos, maxPhotos;
  final List<String> stages, banks;

  /// pay[n]: tiền 1 hồ sơ có n ảnh đạt
  final List<int> pay;

  /// webClientId cho Đăng nhập bằng Google; trống = máy chủ chưa bật
  final String google;

  int payFor(int n) => pay[n.clamp(0, pay.length - 1)];
  String statusLabel(String s) => status[s]?[1] ?? s;
  String statusTone(String s) => status[s]?[2] ?? 'draft';
}

late Cfg cfg;

/// Đăng nhập hay chưa: màn gốc nghe để chuyển giữa Đăng nhập và app.
final authed = ValueNotifier<bool>(false);

/// Số hồ sơ CTV cần xử lý (nháp + bị trả lại), máy chủ gửi kèm mọi trang.
final badge = ValueNotifier<int>(0);

String? _token;
const _store = FlutterSecureStorage();
const _staffHome = ['/duyet', '/ke-toan'];

class ApiError implements Exception {
  ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

String errMsg(Object e) => e is ApiError ? e.message : '$e';

List<String> msgsOf(Json j) => (j['msgs'] as List?)?.map((e) => '$e').toList() ?? const [];

Future<void> start() async {
  String? t;
  try {
    t = await _store.read(key: 'token');
  } catch (_) {
    t = null; // kho khoá của máy hỏng: coi như chưa đăng nhập
  }
  final r = await http.get(Uri.parse('$base/app.json')).timeout(const Duration(seconds: 20));
  cfg = Cfg.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Json);
  _token = t;
  authed.value = t != null;
}

bool loggedIn() => _token != null;

Future<void> setToken(String? t) async {
  _token = t;
  authed.value = t != null;
  try {
    if (t != null) {
      await _store.write(key: 'token', value: t);
    } else {
      await _store.delete(key: 'token');
    }
  } catch (_) {/* vẫn dùng được trong phiên này */}
}

Map<String, String> authHeaders() => {'X-App': '1', if (_token != null) 'Authorization': 'Bearer $_token'};

/// Ảnh của hồ sơ (cần token). goc: ảnh gốc, không thì ảnh thu nhỏ 1568px.
String photoUrl(int pid, {bool goc = false}) => '$base/anh/$pid${goc ? '?goc=1' : ''}';

Future<Json> _handle(Object? j, int status, String path) async {
  if (j is! Json) throw ApiError('Máy chủ đang lỗi (mã $status). Thử lại sau ít phút.');
  final url = j['url'];
  // app chỉ cho CTV: không giữ phiên admin, kế toán
  if (j['token'] is String && !_staffHome.contains(url)) await setToken(j['token'] as String);
  if (j['badge'] is num && (j['badge'] as num).toInt() != badge.value) badge.value = (j['badge'] as num).toInt();
  // Hết phiên, đổi mật khẩu, tài khoản bị khoá: về đăng nhập.
  final locked = status == 403 && '${j['error'] ?? ''}'.contains('đã bị khoá');
  if ((url == '/login' || locked) && !path.startsWith('/login')) {
    final ms = msgsOf(j);
    final e = '${j['error'] ?? ''}';
    final msg = e.isNotEmpty ? e : ms.isNotEmpty ? ms.first : 'Hết phiên đăng nhập, đăng nhập lại nhé.';
    if (_token != null) {
      // nhiều màn cùng gọi: báo 1 lần. Xoá token là màn gốc tự đưa về đăng nhập.
      await setToken(null);
      toast(msg);
    }
    throw ApiError(msg);
  }
  final e = j['error'];
  if (e != null && '$e'.isNotEmpty && e != false) throw ApiError('$e');
  if (status >= 400) throw ApiError('Có lỗi xảy ra (mã $status).');
  return j;
}

Object? _decode(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return null; // không phải JSON
  }
}

/// GET khi không có body, POST form khi có body.
Future<Json> api(String path, [Map<String, String>? body]) async {
  final uri = Uri.parse(base + path);
  http.Response r;
  try {
    r = body == null
        ? await http.get(uri, headers: authHeaders()).timeout(const Duration(seconds: 60))
        : await http.post(uri, headers: authHeaders(), body: body).timeout(const Duration(seconds: 60));
  } on SocketException {
    throw ApiError('Mất kết nối. Kiểm tra mạng rồi thử lại.');
  } on http.ClientException {
    throw ApiError('Mất kết nối. Kiểm tra mạng rồi thử lại.');
  } on TimeoutException {
    throw ApiError('Máy chủ phản hồi chậm. Kiểm tra mạng rồi thử lại.');
  }
  return _handle(_decode(r.bodyBytes), r.statusCode, path);
}

/// 1 file gửi kèm: tên trường form, đường dẫn trong máy, tên file, kiểu.
class UpFile {
  const UpFile(this.field, this.path, this.name, [this.mime = 'image/jpeg']);
  final String field, path, name, mime;
}

/// Tải ảnh lên (multipart) có báo % (0..1).
Future<Json> upload(String path, List<UpFile> files, {Map<String, String> fields = const {}, void Function(double)? onProgress}) async {
  final uri = Uri.parse(base + path);
  final req = http.MultipartRequest('POST', uri)..headers.addAll(authHeaders());
  req.fields.addAll(fields);
  for (final f in files) {
    final parts = f.mime.split('/');
    req.files.add(await http.MultipartFile.fromPath(f.field, f.path, filename: f.name,
        contentType: parts.length == 2 ? MediaType(parts[0], parts[1]) : null));
  }
  final total = req.contentLength;
  final body = req.finalize();
  final sreq = http.StreamedRequest('POST', uri)
    ..headers.addAll(req.headers)
    ..contentLength = total;
  var sent = 0;
  body.listen((chunk) {
    sent += chunk.length;
    if (total > 0) onProgress?.call(sent / total);
    sreq.sink.add(chunk);
  }, onDone: () => sreq.sink.close(), onError: (Object e) => sreq.sink.addError(e), cancelOnError: true);

  final client = http.Client();
  try {
    final res = await client.send(sreq).timeout(const Duration(minutes: 10));
    final bytes = await res.stream.toBytes();
    return await _handle(_decode(bytes), res.statusCode, path);
  } on SocketException {
    throw ApiError('Mất kết nối khi tải ảnh. Kiểm tra mạng rồi thử lại.');
  } on http.ClientException {
    throw ApiError('Mất kết nối khi tải ảnh. Kiểm tra mạng rồi thử lại.');
  } on TimeoutException {
    throw ApiError('Tải ảnh quá lâu. Kiểm tra mạng rồi thử lại.');
  } finally {
    client.close();
  }
}

@visibleForTesting
void debugSetCfg(Cfg c) => cfg = c;
