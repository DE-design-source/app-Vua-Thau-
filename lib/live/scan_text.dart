// Lọc chữ quét được trên khung ngắm (ML Kit đọc trên máy): SĐT Việt Nam và tên công ty / nhà thầu trên bảng hiệu.
// Không phụ thuộc camera, dùng chung cho Android và test.

/// 1 khối chữ đọc được; box: toạ độ 0..1 trong khung hình đã xoay thẳng.
class TextPiece {
  const TextPiece(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;
  double get area => (right - left).abs() * (bottom - top).abs();
}

/// Kết quả lọc 1 khung hình.
class ScanFound {
  const ScanFound({this.phone = '', this.company = '', this.phoneBox, this.companyBox, this.anyText = false});
  final String phone; // 10-11 số, bắt đầu bằng 0
  final String company;
  final TextPiece? phoneBox, companyBox;
  final bool anyText;
}

// Số có thể có dấu cách / chấm / gạch giữa các cụm: 0906 909 901, 0906.909.901, +84 906 909 901
final _phoneRE = RegExp(r'(?:\+?84|0)[\s.\-]?\d(?:[\s.\-]?\d){7,10}');

/// SĐT Việt Nam trong 1 chuỗi (di động 10 số đầu 03/05/07/08/09, bàn 11 số đầu 02). Không có: ''.
String phoneIn(String s) {
  for (final m in _phoneRE.allMatches(s)) {
    var d = m.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('84')) d = '0${d.substring(2)}';
    if (d.length == 10 && RegExp(r'^0[35789]').hasMatch(d)) return d;
    if (d.length == 11 && d.startsWith('02')) return d;
  }
  return '';
}

/// "0906909901" -> "0906 909 901" (dễ đọc trên màn hình).
String prettyPhone(String d) {
  if (d.length == 10) return '${d.substring(0, 4)} ${d.substring(4, 7)} ${d.substring(7)}';
  if (d.length == 11) return '${d.substring(0, 3)} ${d.substring(3, 7)} ${d.substring(7)}';
  return d;
}

// Chữ hay có trên bảng hiệu nhà thầu (ML Kit có khi mất dấu: so cả bản không dấu)
const _keys = [
  'CONG TY', 'CTY', 'TNHH', 'CO PHAN', 'XAY DUNG', 'KIEN TRUC', 'NOI THAT', 'THIET KE', 'THI CONG', 'TU VAN', 'DAU TU',
  'CONSTRUCTION', 'ARCHITECT', 'DESIGN', 'BUILD', 'GROUP', 'HOME', 'DECOR', 'XD', 'TK', 'JSC', 'CO.,LTD', 'CO., LTD',
];

const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Bỏ dấu tiếng Việt, viết hoa: "Công ty" -> "CONG TY".
String plain(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = _from.indexOf(c);
    b.write(i >= 0 ? _to[i] : c);
  }
  return b.toString().toUpperCase();
}

int _hits(String s) {
  final p = ' ${plain(s).replaceAll(RegExp(r'[^A-Z0-9.,]+'), ' ')} ';
  var n = 0;
  for (final k in _keys) {
    if (p.contains(' $k ') || (k.length > 3 && p.contains(k))) n++;
  }
  return n;
}

/// Còn chữ ngoài các từ khoá (ít nhất 3 chữ cái), tức là có tên riêng.
bool _hasName(String s) {
  var p = ' ${plain(s).replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')} ';
  for (final k in _keys) {
    p = p.replaceAll(' ${k.replaceAll(RegExp(r'[^A-Z0-9 ]'), '')} ', ' ');
  }
  return p.replaceAll(RegExp(r'[^A-Z]'), '').length >= 3;
}

String _clean(String s) {
  var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // bỏ phần SĐT / hotline dính cùng dòng
  t = t.replaceAll(RegExp(r'(?:hotline|đt|dt|tel|sđt|sdt|đ\.t)\s*[:.]?\s*', caseSensitive: false), '');
  t = t.replaceAll(_phoneRE, '').replaceAll(RegExp(r'[\s:;,.\-]+$'), '').trim();
  return t.length > 90 ? t.substring(0, 90).trim() : t;
}

/// Lọc các khối chữ của 1 khung hình: SĐT (khối chữ to nhất có số) và tên công ty (khối nhiều từ khoá nhất, chữ to).
ScanFound findInPieces(List<TextPiece> pieces) {
  TextPiece? phoneBox, companyBox;
  var phone = '';
  for (final p in pieces) {
    final ph = phoneIn(p.text);
    if (ph.isNotEmpty && (phoneBox == null || p.area > phoneBox.area)) {
      phone = ph;
      phoneBox = p;
    }
  }
  var best = 0.0;
  var company = '';
  for (final p in pieces) {
    final h = _hits(p.text);
    if (h == 0) continue;
    final name = _clean(p.text);
    if (!_hasName(name)) continue; // chỉ "CÔNG TY" / "CTY TNHH": chưa thấy tên
    final score = h * 10 + p.area * 100;
    if (score > best) {
      best = score;
      company = name;
      companyBox = p;
    }
  }
  return ScanFound(phone: phone, company: company, phoneBox: phoneBox, companyBox: companyBox, anyText: pieces.isNotEmpty);
}

/// Giữ kết quả ổn định giữa các khung hình: chỉ hiện giá trị thấy ở ít nhất [need] trong [window] lần quét gần nhất,
/// và giữ thêm [hold] sau lần cuối thấy (đưa máy lệch đi một chút không mất).
class Steady {
  Steady({this.window = 4, this.need = 2, this.hold = const Duration(seconds: 4)});
  final int window, need;
  final Duration hold;
  final _seen = <String>[];
  String value = '';
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  String push(String v, DateTime now) {
    _seen.add(v);
    if (_seen.length > window) _seen.removeAt(0);
    if (v.isNotEmpty && _seen.where((x) => x == v).length >= need) {
      value = v;
      _at = now;
    } else if (value.isNotEmpty && now.difference(_at) > hold) {
      value = '';
    }
    return value;
  }
}
