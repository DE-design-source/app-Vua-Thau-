// Nói chuyện với máy chủ Go (repo DE-design-source/VuaThau), API REST dưới /api/v1, dùng chung với web quản lý.
// Mọi response là {success, data, error}; đăng nhập bằng JWT (Authorization: Bearer).
// Luật kiểm ảnh, luật tiền, AI, Drive đều nằm ở máy chủ.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'lfile.dart';
import 'toast.dart';

/// Đổi máy chủ khi build: flutter build apk --dart-define=API_URL=https://...
/// (máy ảo Android gọi backend chạy trên máy tính: http://10.0.2.2:8080)
const host = String.fromEnvironment('API_URL', defaultValue: 'https://map.vuathau.com.vn');
const base = '$host/api/v1';

typedef Json = Map<String, dynamic>;

/// Cấu hình chung lấy từ máy chủ (GET /config): trạng thái, luật tiền, giai đoạn, ngân hàng...
class Cfg {
  Cfg.fromJson(Json j)
      : status = ((j['statuses'] as Map?) ?? const {}).map((k, v) {
          final m = (v as Map?) ?? const {};
          return MapEntry('$k', ['${m['label'] ?? k}', '${m['ctv_label'] ?? m['label'] ?? k}', '${m['tone'] ?? 'draft'}']);
        }),
        payMin = (j['pay_min'] as num).toInt(),
        minPhotos = (j['min_photos'] as num).toInt(),
        maxPhotos = (j['max_photos'] as num).toInt(),
        stages = ((j['stages'] as List?) ?? const []).map((e) => '$e').toList(),
        banks = ((j['banks'] as List?) ?? const []).map((e) => '$e').toList(),
        pay = ((j['pay'] as List?) ?? const [0]).map((e) => (e as num).toInt()).toList(),
        videoBonus = (j['video_bonus'] as num?)?.toInt() ?? 0,
        google = '${j['google_client_id'] ?? ''}',
        ntForm = '${j['nt_form'] ?? ''}';

  /// Form đăng ký nhà thầu (Lark): màn đăng nhập chọn "Nhà thầu" mà SĐT chưa có tài khoản
  final String ntForm;

  /// mã: [nhãn nội bộ, nhãn cho CTV, tông màu]
  final Map<String, List<String>> status;
  final int payMin, minPhotos, maxPhotos;
  final List<String> stages, banks;

  /// pay[n]: tiền 1 hồ sơ có n ảnh đạt
  final List<int> pay;

  /// Thưởng hồ sơ có video (cộng khi hồ sơ đủ ảnh để được trả tiền); 0 = không thưởng / máy chủ cũ
  final int videoBonus;


  /// webClientId cho Đăng nhập bằng Google; trống = máy chủ chưa bật
  final String google;

  int payFor(int n) => pay.isEmpty ? 0 : pay[n.clamp(0, pay.length - 1)];
  String statusLabel(String s) => status[s]?[1] ?? s;
  String statusTone(String s) => status[s]?[2] ?? 'draft';
}

late Cfg cfg;

/// Đăng nhập hay chưa: màn gốc nghe để chuyển giữa Đăng nhập và app.
final authed = ValueNotifier<bool>(false);

/// Số hồ sơ CTV cần xử lý (nháp + bị trả lại): `todo` của /ctv/home và /me.
final badge = ValueNotifier<int>(0);

/// Người đang đăng nhập (User của máy chủ). Mở lại app: lấy lại qua /me.
final me = ValueNotifier<Json?>(null);

String? _token;
const _store = FlutterSecureStorage();

class ApiError implements Exception {
  ApiError(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

String errMsg(Object e) => e is ApiError ? e.message : '$e';

/// Câu báo của thao tác ghi: data.message + data.messages (nếu có).
List<String> msgsOf(Json j) => [
      if (j['message'] is String && (j['message'] as String).isNotEmpty) j['message'] as String,
      ...?(j['messages'] as List?)?.map((e) => '$e'),
    ];

Future<void> start() async {
  String? t;
  try {
    t = await _store.read(key: 'token');
  } catch (_) {
    t = null; // kho khoá của máy hỏng: coi như chưa đăng nhập
  }
  cfg = Cfg.fromJson(await api('/config'));
  _token = t;
  // mở lại app: biết vai trò trước khi dựng màn (CTV / nhà thầu có giao diện khác nhau)
  if (t != null) await loadMe();
  // loadMe gặp 401 (hết phiên, bị khoá) đã xoá token: dùng _token, không dùng t cũ (không thì vào app mà không có token)
  authed.value = _token != null;
}

bool loggedIn() => _token != null;

Future<void> setToken(String? t) async {
  _token = t;
  if (t == null) me.value = null;
  authed.value = t != null;
  try {
    if (t != null) {
      await _store.write(key: 'token', value: t);
    } else {
      await _store.delete(key: 'token');
    }
  } catch (_) {/* vẫn dùng được trong phiên này */}
}

Map<String, String> authHeaders() => {if (_token != null) 'Authorization': 'Bearer $_token'};

/// Ảnh của hồ sơ (cần token). goc: ảnh gốc, không thì ảnh thu nhỏ 1568px.
String photoUrl(int pid, {bool goc = false}) => '$base/photos/$pid${goc ? '?original=1' : ''}';

Future<Json> _handle(Object? j, int status, String path) async {
  if (j is! Map) throw ApiError('Máy chủ đang lỗi (mã $status). Thử lại sau ít phút.', status);
  final ok = j['success'] == true && status < 400;
  if (!ok) {
    final e = '${j['error'] ?? ''}';
    // Hết phiên, đổi mật khẩu ở máy khác, tài khoản bị khoá: về đăng nhập.
    final locked = status == 403 && e.contains('khoá');
    if ((status == 401 || locked) && !path.startsWith('/auth/')) {
      final msg = e.isNotEmpty ? e : 'Hết phiên đăng nhập, đăng nhập lại nhé.';
      if (_token != null) {
        // nhiều màn cùng gọi: báo 1 lần. Xoá token là màn gốc tự đưa về đăng nhập.
        await setToken(null);
        toast(msg);
      }
      throw ApiError(msg, status);
    }
    throw ApiError(e.isNotEmpty ? e : 'Có lỗi xảy ra (mã $status).', status);
  }
  final data = j['data'];
  return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
}

Object? _decode(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return null; // không phải JSON
  }
}

/// Gọi /api/v1[path]: GET khi không có body; POST/PUT gửi JSON; DELETE. Trả `data` của envelope.
Future<Json> api(String path, {String method = 'GET', Object? body}) async {
  final uri = Uri.parse(base + path);
  final headers = {...authHeaders(), if (body != null) 'Content-Type': 'application/json; charset=utf-8'};
  final req = http.Request(method, uri)..headers.addAll(headers);
  if (body != null) req.body = jsonEncode(body);
  final client = http.Client();
  http.Response r;
  try {
    r = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 60)));
  } on SocketException {
    throw ApiError('Mất kết nối. Kiểm tra mạng rồi thử lại.');
  } on http.ClientException {
    throw ApiError('Mất kết nối. Kiểm tra mạng rồi thử lại.');
  } on TimeoutException {
    throw ApiError('Máy chủ phản hồi chậm. Kiểm tra mạng rồi thử lại.');
  } finally {
    client.close();
  }
  return _handle(_decode(r.bodyBytes), r.statusCode, path);
}

Future<Json> post(String path, [Object? body]) => api(path, method: 'POST', body: body ?? const <String, dynamic>{});
Future<Json> put(String path, Object body) => api(path, method: 'PUT', body: body);
Future<Json> delete(String path) => api(path, method: 'DELETE');

/// 1 file gửi kèm: tên trường form, đường dẫn trong máy, tên file, kiểu.
class UpFile {
  const UpFile(this.field, this.path, this.name, [this.mime = 'image/jpeg']);
  final String field, path, name, mime;
}

/// Tải ảnh lên (multipart POST) có báo % (0..1).
Future<Json> upload(String path, List<UpFile> files, {Map<String, String> fields = const {}, void Function(double)? onProgress}) async {
  final uri = Uri.parse(base + path);
  final req = http.MultipartRequest('POST', uri)..headers.addAll(authHeaders());
  req.fields.addAll(fields);
  for (final f in files) {
    final parts = f.mime.split('/');
    req.files.add(await multipartOf(f.field, f.path, f.name, parts.length == 2 ? MediaType(parts[0], parts[1]) : null));
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

/// Lấy lại thông tin người đang đăng nhập (tên cho lời chào) khi mở lại app.
Future<void> loadMe() async {
  try {
    final j = await api('/me');
    if (j['user'] is Map) me.value = (j['user'] as Map).cast<String, dynamic>();
    if (j['todo'] is num) badge.value = (j['todo'] as num).toInt();
  } catch (_) {/* lời chào chung */}
}

@visibleForTesting
void debugSetCfg(Cfg c) => cfg = c;
