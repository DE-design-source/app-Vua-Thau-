import 'package:flutter_test/flutter_test.dart';
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
  });

  test('chữ cái đầu tên', () {
    expect(initials('Nguyễn Văn An'), 'NA');
    expect(initials('an'), 'A');
    expect(initials(''), '?');
  });

  test('lấy id hồ sơ từ url máy chủ trả về', () {
    expect(houseIdOf('/nha/123#anh'), 123);
    expect(houseIdOf('/nha/moi'), isNull);
    expect(houseIdOf('/cua-toi'), isNull);
  });

  test('mã Timemark ổn định, 14 ký tự', () {
    final d = StampData(DateTime.fromMillisecondsSinceEpoch(1762400000000), const Pos(21.0285, 105.8542, 5), '');
    final a = stampCode(d), b = stampCode(d);
    expect(a, b);
    expect(a.length, 14);
    expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(a), isTrue);
  });
}
