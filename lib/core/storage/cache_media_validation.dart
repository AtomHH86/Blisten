import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 检查响应及容器边界，拒绝明显的错误页、空文件与截断内容。
/// 这不是完整解码或音频质量验证；只读取头部和各容器块的边界。
Future<int> validateCacheDownload(File file, {
  required int? statusCode,
  String? contentType,
  int? contentLength,
}) async {
  final size = await file.length();
  final type = (contentType ?? '').toLowerCase();
  if (statusCode != 200 || size <= 0 ||
      (contentLength != null && contentLength >= 0 && size != contentLength) ||
      type.startsWith('text/') || type.contains('json') || type.contains('html')) {
    throw const FormatException('下载内容不完整或不是音频');
  }
  final input = await file.open();
  try {
    Future<Uint8List> read(int at, int count) async {
      if (at < 0 || at + count > size) throw const FormatException('音频内容被截断');
      await input.setPosition(at);
      final bytes = await input.read(count);
      if (bytes.length != count) throw const FormatException('音频内容被截断');
      return bytes;
    }

    final header = await read(0, size < 12 ? size : 12);
    String label(Uint8List bytes, int start, int end) =>
        ascii.decode(bytes.sublist(start, end), allowInvalid: true);
    if (header.length >= 12 && label(header, 0, 4) == 'RIFF' &&
        label(header, 8, 12) == 'WAVE') {
      if (ByteData.sublistView(header).getUint32(4, Endian.little) + 8 != size) {
        throw const FormatException('WAVE 长度不完整');
      }
      var offset = 12;
      var format = false;
      var audio = false;
      while (offset < size) {
        final chunk = await read(offset, 8);
        final length = ByteData.sublistView(chunk).getUint32(4, Endian.little);
        final end = offset + 8 + length;
        if (end > size) throw const FormatException('WAVE 分块被截断');
        final kind = label(chunk, 0, 4);
        if (kind == 'fmt ') format = length >= 16;
        if (kind == 'data') audio = length > 0;
        offset = end + (length.isOdd ? 1 : 0);
      }
      if (!format || !audio || offset != size) throw const FormatException('WAVE 音频结构不完整');
    } else if (header.length >= 8 && label(header, 4, 8) == 'ftyp') {
      var offset = 0;
      var initialization = false;
      var audio = false;
      var boxes = 0;
      while (offset < size) {
        if (++boxes > 100000) throw const FormatException('音频分块过多');
        final box = await read(offset, 8);
        var length = ByteData.sublistView(box).getUint32(0);
        var headerSize = 8;
        if (length == 1) {
          length = ByteData.sublistView(await read(offset + 8, 8)).getUint64(0);
          headerSize = 16;
        } else if (length == 0) {
          length = size - offset;
        }
        if (length < headerSize || offset + length > size) {
          throw const FormatException('MP4 分块被截断');
        }
        final kind = label(box, 4, 8);
        if (kind == 'moov') initialization = length > headerSize;
        if (kind == 'mdat') audio = length > headerSize;
        if (kind == 'ftyp' && length < headerSize + 8) {
          throw const FormatException('MP4 文件头不完整');
        }
        offset += length;
      }
      if (!initialization || !audio) throw const FormatException('MP4 音频结构不完整');
    } else if (header.length >= 4 && label(header, 0, 4) == 'fLaC') {
      var offset = 4;
      var first = true;
      var last = false;
      var blocks = 0;
      while (!last) {
        if (++blocks > 128) throw const FormatException('FLAC 元数据过多');
        final block = await read(offset, 4);
        final length = (block[1] << 16) | (block[2] << 8) | block[3];
        if (first && ((block[0] & 0x7f) != 0 || length != 34)) {
          throw const FormatException('FLAC 文件头不完整');
        }
        if (offset + 4 + length > size) throw const FormatException('FLAC 元数据被截断');
        first = false;
        last = (block[0] & 0x80) != 0;
        offset += 4 + length;
      }
      final frame = await read(offset, 6);
      if (frame[0] != 0xff || (frame[1] & 0xfc) != 0xf8) {
        throw const FormatException('FLAC 音频帧缺失');
      }
    } else {
      throw const FormatException('下载内容不是支持的音频容器');
    }
    return size;
  } finally {
    await input.close();
  }
}
