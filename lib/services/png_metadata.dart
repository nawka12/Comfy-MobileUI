import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

class PngMetadata {
  static const _signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

  /// Embed metadata as PNG tEXt chunks (ComfyUI-compatible)
  static Uint8List embed(Uint8List png, Map<String, String> metadata) {
    final chunks = _parseChunks(png);
    if (chunks.isEmpty) return png;

    final out = BytesBuilder();
    out.add(_signature);

    for (final chunk in chunks) {
      if (chunk.type == 'IEND') {
        for (final entry in metadata.entries) {
          _writeChunk(out, 'tEXt', _textData(entry.key, entry.value));
        }
      }
      _writeChunk(out, chunk.type, chunk.data);
    }

    return out.toBytes();
  }

  /// Read all tEXt chunk metadata from a PNG file
  static Map<String, String> read(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return {};
    final bytes = file.readAsBytesSync();
    return readFromBytes(bytes);
  }

  /// Read all tEXt chunk metadata from PNG bytes
  static Map<String, String> readFromBytes(Uint8List bytes) {
    final chunks = _parseChunks(bytes);
    final result = <String, String>{};
    for (final chunk in chunks) {
      if (chunk.type == 'tEXt') {
        final data = chunk.data;
        final nullIdx = data.indexOf(0);
        if (nullIdx > 0) {
          final key = utf8.decode(data.sublist(0, nullIdx));
          final value = utf8.decode(data.sublist(nullIdx + 1));
          result[key] = value;
        }
      }
    }
    return result;
  }

  static List<_PngChunk> _parseChunks(Uint8List bytes) {
    if (bytes.length < 8) return [];
    final chunks = <_PngChunk>[];
    int offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = _readUint32(bytes, offset);
      offset += 4;
      if (offset + 4 > bytes.length) break;
      final type = utf8.decode(bytes.sublist(offset, offset + 4));
      offset += 4;
      if (offset + length > bytes.length) break;
      final data = bytes.sublist(offset, offset + length);
      offset += length + 4;
      chunks.add(_PngChunk(type, data));
    }
    return chunks;
  }

  static Uint8List _textData(String key, String value) {
    final encoded = utf8.encode(key);
    final valueEncoded = utf8.encode(value);
    return Uint8List.fromList([...encoded, 0, ...valueEncoded]);
  }

  static void _writeChunk(BytesBuilder out, String type, List<int> data) {
    _writeUint32(out, data.length);
    out.add(utf8.encode(type));
    out.add(data);
    final crc = _crc32(Uint8List.fromList([...utf8.encode(type), ...data]));
    _writeUint32(out, crc);
  }

  static int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) | bytes[offset + 3];

  static void _writeUint32(BytesBuilder out, int value) {
    out.addByte((value >> 24) & 0xFF);
    out.addByte((value >> 16) & 0xFF);
    out.addByte((value >> 8) & 0xFF);
    out.addByte(value & 0xFF);
  }

  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        if (c & 1 != 0) {
          c = 0xEDB88320 ^ (c >> 1);
        } else {
          c >>= 1;
        }
      }
      table[n] = c;
    }
    return table;
  }

  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < data.length; i++) {
      crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}

class _PngChunk {
  final String type;
  final Uint8List data;
  _PngChunk(this.type, this.data);
}
