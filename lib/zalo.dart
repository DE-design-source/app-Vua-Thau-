// Mở khung chat Zalo theo số điện thoại (https://zalo.me/0912345678): máy có Zalo thì vào thẳng app Zalo, không thì mở web.
// Zalo không cho app khác điền sẵn lời nhắn: app chép lời nhắn trước, người dùng dán vào khung chat.
import 'package:url_launcher/url_launcher.dart';

final _vnMobile = RegExp(r'^(?:\+?84|0)([35789]\d{8})$');

/// SĐT di động Việt Nam (0912 345 678, +84912345678, 091.234.5678...) về dạng 0912345678; không phải SĐT di động thì null.
String? zaloPhone(String s) {
  final m = _vnMobile.firstMatch(s.trim().replaceAll(RegExp(r'[\s.\-()]'), ''));
  return m == null ? null : '0${m.group(1)}';
}

/// Link chat Zalo của 1 SĐT; SĐT không hợp lệ thì null.
Uri? zaloChatUri(String phone) {
  final p = zaloPhone(phone);
  return p == null ? null : Uri(scheme: 'https', host: 'zalo.me', pathSegments: [p]);
}

/// Mở chat Zalo; false khi SĐT sai hoặc máy không mở được.
Future<bool> openZaloChat(String phone) async {
  final u = zaloChatUri(phone);
  if (u == null) return false;
  try {
    return await launchUrl(u, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
