import 'package:flutter_test/flutter_test.dart';
import 'package:vuathau/api.dart';
import 'package:vuathau/screens/submit.dart' show houseIdOf;
import 'package:vuathau/stamp.dart';
import 'package:vuathau/ui.dart';

void main() {
  test('money định dạng kiểu Việt Nam', () {
    expect(money(0), '0đ');
    expect(money(35000), '35.000đ');
    expect(money(1250000), '1.250.000đ');
    expect(money(-50000), '-50.000đ');
    expect(money(null), '0đ');
  });

  test('ngày giờ từ chuỗi máy chủ', () {
    expect(vnDate('2026-11-06 12:54:53'), '06/11/2026');
    expect(vnTime('2026-11-06 12:54:53'), '12:54 06/11/2026');
    expect(vnDate(''), '');
    expect(vnDate(null), '');
    expect(vnTime(''), '');
  });

  test('ngày giờ RFC 3339 của API mới', () {
    expect(vnDate('2026-11-13T14:13:05+07:00'), '13/11/2026');
    expect(vnTime('2026-11-13T14:13:05+07:00'), '14:13 13/11/2026');
    // múi giờ khác: đổi về giờ Việt Nam
    expect(vnTime('2026-11-13T20:30:00Z'), '03:30 14/11/2026');
    expect(vnDate('2026-11-13T20:30:00Z'), '14/11/2026');
    expect(vnTime('2026-11-13T14:13:05.123+07:00'), '14:13 13/11/2026');
  });

  test('giờ chụp ảnh YYYY-MM-DD HH:MM', () {
    expect(vnTime('2026-11-13 14:10'), '14:10 13/11/2026');
    expect(vnDate('2026-11-13 14:10'), '13/11/2026');
    expect(vnDate('2026-11-13'), '13/11/2026');
    expect(vnTime('2026-11-13'), '13/11/2026');
  });

  test('chữ cái đầu tên', () {
    expect(initials('Nguyễn Văn An'), 'NA');
    expect(initials('an'), 'A');
    expect(initials(''), '?');
  });

  test('lấy id hồ sơ từ kết quả POST /houses', () {
    expect(houseIdOf({'house_id': 123}), 123);
    expect(houseIdOf({'house_id': null}), isNull);
    expect(houseIdOf({'message': 'x'}), isNull);
  });

  test('câu báo của thao tác ghi', () {
    expect(msgsOf({'message': 'Đã nhận 5 ảnh', 'messages': ['Ảnh 2 trùng']}), ['Đã nhận 5 ảnh', 'Ảnh 2 trùng']);
    expect(msgsOf({'message': ''}), isEmpty);
    expect(msgsOf({}), isEmpty);
  });

  test('cấu hình từ GET /config', () {
    final c = Cfg.fromJson({
      'statuses': {
        'nhap': {'label': 'Đang soạn', 'ctv_label': 'Chưa gửi', 'tone': 'draft'},
        'da_duyet': {'label': 'Đã duyệt', 'ctv_label': 'Chờ thanh toán', 'tone': 'ok'},
      },
      'min_photos': 5,
      'max_photos': 20,
      'pay_min': 5,
      'pay': [0, 0, 0, 0, 0, 35000, 50000],
      'stages': ['Đào móng / làm móng'],
      'banks': ['Vietcombank'],
      'google_client_id': '',
    });
    expect(c.statusLabel('da_duyet'), 'Chờ thanh toán');
    expect(c.statusTone('da_duyet'), 'ok');
    expect(c.statusLabel('la'), 'la');
    expect(c.payFor(5), 35000);
    expect(c.payFor(12), 50000);
    expect(c.google, '');
  });

  test('mã Timemark ổn định, 14 ký tự', () {
    final d = StampData(DateTime.fromMillisecondsSinceEpoch(1762400000000), const Pos(21.0285, 105.8542, 5), '');
    final a = stampCode(d), b = stampCode(d);
    expect(a, b);
    expect(a.length, 14);
    expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(a), isTrue);
  });
}
