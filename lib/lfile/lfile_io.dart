import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:path_provider/path_provider.dart';

Future<Uint8List> readLocal(String path) => File(path).readAsBytes();

Future<int> localLength(String path) => File(path).length();

void deleteLocal(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
}

/// Lưu ảnh đã xử lý vào bộ nhớ tạm, trả đường dẫn.
Future<String> saveTemp(Uint8List bytes, String name) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

Widget localImage(String path, {BoxFit? fit, int? cacheWidth}) => Image.file(File(path), fit: fit, cacheWidth: cacheWidth);

Future<http.MultipartFile> multipartOf(String field, String path, String name, MediaType? type) =>
    http.MultipartFile.fromPath(field, path, filename: name, contentType: type);
