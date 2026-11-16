import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

// Ảnh đã in dải chữ giữ trong bộ nhớ (web không có thư mục tạm): khoá "mem:<n>".
final _mem = <String, Uint8List>{};
var _n = 0;

Future<Uint8List> readLocal(String path) async => _mem[path] ?? await XFile(path).readAsBytes();

Future<int> localLength(String path) async => _mem[path]?.length ?? await XFile(path).length();

void deleteLocal(String path) => _mem.remove(path);

Future<String> saveTemp(Uint8List bytes, String name) async {
  final k = 'mem:${_n++}/$name';
  _mem[k] = bytes;
  return k;
}

Widget localImage(String path, {BoxFit? fit, int? cacheWidth}) {
  final b = _mem[path];
  return b != null ? Image.memory(b, fit: fit, cacheWidth: cacheWidth, gaplessPlayback: true) : Image.network(path, fit: fit, cacheWidth: cacheWidth);
}

Future<http.MultipartFile> multipartOf(String field, String path, String name, MediaType? type) async =>
    http.MultipartFile.fromBytes(field, await readLocal(path), filename: name, contentType: type);
