import 'package:flutter_test/flutter_test.dart';
import 'package:vuathau/live/scan_text.dart';

TextPiece p(String t, [double size = 0.3]) => TextPiece(t, 0, 0, size, size);

void main() {
  test('phoneIn: các kiểu viết SĐT', () {
    expect(phoneIn('Hotline: 0906 909 901'), '0906909901');
    expect(phoneIn('ĐT 0906.909.901'), '0906909901');
    expect(phoneIn('+84 906 909 901'), '0906909901');
    expect(phoneIn('Tel: 028 3822 1234'), '02838221234');
    expect(phoneIn('1900 1234'), '');
    expect(phoneIn('Giấy phép 012345/GPXD'), '');
    expect(phoneIn('0123456789'), ''); // đầu 01 không còn dùng
  });

  test('prettyPhone', () {
    expect(prettyPhone('0906909901'), '0906 909 901');
  });

  test('findInPieces: tên công ty và SĐT trên bảng hiệu', () {
    final f = findInPieces([
      p('CÔNG TY TNHH TK XD MỘC MINH', 0.5),
      p('Hotline: 0906 909 901', 0.2),
      p('Đơn vị thi công', 0.1),
    ]);
    expect(f.phone, '0906909901');
    expect(f.company, 'CÔNG TY TNHH TK XD MỘC MINH');
    expect(f.anyText, isTrue);
  });

  test('findInPieces: chữ mất dấu, SĐT cùng dòng tên', () {
    final f = findInPieces([p('CONG TY XAY DUNG AN PHAT - DT: 0912345678')]);
    expect(f.phone, '0912345678');
    expect(f.company, 'CONG TY XAY DUNG AN PHAT');
  });

  test('findInPieces: chỉ có chữ "CÔNG TY" thì chưa nhận', () {
    expect(findInPieces([p('CÔNG TY')]).company, '');
    expect(findInPieces([]).anyText, isFalse);
  });

  test('Steady: cần thấy 2 lần, giữ 4 giây', () {
    final s = Steady();
    final t0 = DateTime(2026);
    expect(s.push('0906909901', t0), '');
    expect(s.push('0906909901', t0.add(const Duration(milliseconds: 500))), '0906909901');
    expect(s.push('', t0.add(const Duration(seconds: 2))), '0906909901');
    expect(s.push('', t0.add(const Duration(seconds: 6))), '');
  });
}
