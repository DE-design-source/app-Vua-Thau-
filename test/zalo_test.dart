import 'package:flutter_test/flutter_test.dart';
import 'package:vuathau/screens/report.dart' show reportMessage;
import 'package:vuathau/zalo.dart';

void main() {
  test('SĐT chủ nhà các kiểu viết về dạng 0912345678', () {
    for (final s in ['0912345678', ' 0912 345 678 ', '091.234.5678', '0912-345-678', '(091) 2345678', '+84912345678', '+84 912 345 678', '84912345678']) {
      expect(zaloPhone(s), '0912345678', reason: s);
    }
    expect(zaloChatUri('+84 912 345 678').toString(), 'https://zalo.me/0912345678');
  });

  test('không nhận số không phải di động Việt Nam', () {
    for (final s in ['', '   ', '12345', '0112345678', '09123456789', '+1 912 345 678', '02412345678', 'tel:0912345678', 'https://evil.com/0912345678']) {
      expect(zaloPhone(s), isNull, reason: s);
      expect(zaloChatUri(s), isNull, reason: s);
    }
  });

  test('lời nhắn soạn sẵn gửi chủ nhà', () {
    final day = DateTime(2026, 11, 4);
    expect(
      reportMessage(name: 'Chị Tuyết', address: '12 Lê Lợi, Bình Chánh', stage: 'Xây thô', day: day),
      'Chào Chị Tuyết, em là cộng tác viên Vua Thầu. Hôm nay (04/11) em đã chụp cập nhật công trình 12 Lê Lợi, Bình Chánh, giai đoạn xây thô ạ.',
    );
    expect(
      reportMessage(name: ' ', address: '', stage: '', day: day, link: 'https://vuathau.com.vn/bc/ab12'),
      'Chào anh/chị, em là cộng tác viên Vua Thầu. Hôm nay (04/11) em đã chụp cập nhật công trình nhà mình ạ.\n'
      'Anh/chị xem ảnh thực tế tại: https://vuathau.com.vn/bc/ab12',
    );
  });
}
