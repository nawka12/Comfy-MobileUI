import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/generation_params.dart';
import 'png_metadata.dart';

class GalleryService extends ChangeNotifier {
  static const _galleryIndexKey = 'gallery_index';
  static const _hiddenIndexKey = 'hidden_gallery_index';
  List<GalleryItem> _items = [];
  List<GalleryItem> _hiddenItems = [];
  String? _galleryDir;

  List<GalleryItem> get items => List.unmodifiable(_items);
  List<GalleryItem> get hiddenItems => List.unmodifiable(_hiddenItems);

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _galleryDir = '${dir.path}/ComfyMobile';
    final galleryDir = Directory(_galleryDir!);
    if (!await galleryDir.exists()) {
      await galleryDir.create(recursive: true);
    }
    await _loadIndex();
    await _loadHiddenIndex();
  }

  String get _galleryDirPath => _galleryDir!;

  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_galleryIndexKey);
    if (json == null || json.isEmpty) {
      _items = [];
      return;
    }
    try {
      final data = jsonDecode(json) as List<dynamic>;
      _items = data
          .map((e) => GalleryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _items = [];
    }
  }

  Future<void> _saveIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_galleryIndexKey, json);
  }

  Future<void> _loadHiddenIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_hiddenIndexKey);
    if (json == null || json.isEmpty) {
      _hiddenItems = [];
      return;
    }
    try {
      final data = jsonDecode(json) as List<dynamic>;
      _hiddenItems = data
          .map((e) => GalleryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _hiddenItems = [];
    }
  }

  Future<void> _saveHiddenIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_hiddenItems.map((e) => e.toJson()).toList());
    await prefs.setString(_hiddenIndexKey, json);
  }

  Future<GalleryItem> addImage(
    Uint8List imageData,
    GenerationParams params, {
    String? workflowJson,
    String? comfyConfig,
  }) async {
    if (_galleryDir == null) await init();
    final id = const Uuid().v4();
    final filePath = '$_galleryDirPath/$id.png';
    final file = File(filePath);

    Uint8List finalBytes = imageData;
    final metadata = <String, String>{};
    if (workflowJson != null) metadata['prompt'] = workflowJson;
    if (comfyConfig != null) metadata['comfy_mobile'] = comfyConfig;
    if (metadata.isNotEmpty) {
      finalBytes = PngMetadata.embed(finalBytes, metadata);
    }

    await file.writeAsBytes(finalBytes);

    final item = GalleryItem(
      id: id,
      filePath: filePath,
      createdAt: DateTime.now(),
      params: params,
    );
    _items.insert(0, item);
    await _saveIndex();
    notifyListeners();
    return item;
  }

  Map<String, String> readImageMetadata(String filePath) {
    return PngMetadata.read(filePath);
  }

  Map<String, String> readImageMetadataFromBytes(Uint8List bytes) {
    return PngMetadata.readFromBytes(bytes);
  }

  Future<void> deleteItem(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final item = _items.removeAt(idx);
    final file = File(item.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await _saveIndex();
    notifyListeners();
  }

  Future<void> deleteAll() async {
    for (final item in _items) {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _items.clear();
    await _saveIndex();
    notifyListeners();
  }

  Future<void> moveToHidden(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final item = _items.removeAt(idx);
    _hiddenItems.insert(0, item);
    await _saveIndex();
    await _saveHiddenIndex();
    notifyListeners();
  }

  Future<void> restoreFromHidden(String id) async {
    final idx = _hiddenItems.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final item = _hiddenItems.removeAt(idx);
    _items.insert(0, item);
    await _saveIndex();
    await _saveHiddenIndex();
    notifyListeners();
  }

  Future<void> deleteHiddenItem(String id) async {
    final idx = _hiddenItems.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final item = _hiddenItems.removeAt(idx);
    final file = File(item.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    await _saveHiddenIndex();
    notifyListeners();
  }

  Future<void> deleteAllHidden() async {
    for (final item in _hiddenItems) {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _hiddenItems.clear();
    await _saveHiddenIndex();
    notifyListeners();
  }

  Future<Uint8List?> loadImageBytes(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  /// Save a gallery image to a public/shared directory so it appears
  /// in the file manager, gallery app, or camera roll.
  Future<String?> saveToSharedLocation(String itemId) async {
    final idx = _items.indexWhere((e) => e.id == itemId);
    if (idx == -1) return null;
    final item = _items[idx];
    final source = File(item.filePath);
    if (!await source.exists()) return null;

    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.kayfahaarukku.comfymobile/save_image');
        final result = await channel.invokeMethod<String?>('saveToPublicGallery', {
          'sourcePath': source.path,
        });
        if (result != null) return result;
      } catch (_) {}
    }

    Directory? targetDir;
    try {
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          targetDir = Directory('${extDir.path}/Pictures/ComfyMobile');
        }
      } else {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          targetDir = Directory('${downloads.path}/ComfyMobile');
        }
      }
    } catch (_) {}

    targetDir ??= Directory('$_galleryDirPath/shared');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final dest = '${targetDir.path}/$itemId.png';
    await source.copy(dest);
    return dest;
  }
}

class GalleryItem {
  final String id;
  final String filePath;
  final DateTime createdAt;
  final GenerationParams params;

  GalleryItem({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.params,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'params': params.toJson(),
      };

  factory GalleryItem.fromJson(Map<String, dynamic> json) => GalleryItem(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        params: GenerationParams.fromJson(
            json['params'] as Map<String, dynamic>? ?? {}),
      );
}
