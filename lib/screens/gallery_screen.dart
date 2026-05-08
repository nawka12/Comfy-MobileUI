import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/architecture_profile.dart';
import '../models/generation_params.dart';
import '../services/gallery_service.dart';
import 'hidden_gallery_screen.dart';
import 'home_screen.dart';

class GalleryScreen extends StatefulWidget {
  final GalleryService galleryService;

  const GalleryScreen({super.key, required this.galleryService});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  Future<void> _deleteItem(GalleryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await widget.galleryService.deleteItem(item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _viewImage(GalleryItem item) async {
    final items = widget.galleryService.items.toList(growable: false);
    final initialIndex = items.indexWhere((i) => i.id == item.id);
    if (initialIndex < 0) return;
    final appState = context.read<AppState>();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _ImageViewer(
          items: items,
          initialIndex: initialIndex,
          galleryService: widget.galleryService,
          appState: appState,
          onDelete: (toDelete) {
            Navigator.of(context).pop();
            _deleteItem(toDelete);
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.galleryService,
      builder: (context, _) {
        final items = widget.galleryService.items;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              items.isNotEmpty ? 'Gallery (${items.length})' : 'Gallery',
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Hidden library',
                onPressed: () {
                  final appState = context.read<AppState>();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider<AppState>.value(
                        value: appState,
                        child: const HiddenGalleryScreen(),
                      ),
                    ),
                  );
                },
              ),
              if (items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: 'Clear all',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear Gallery'),
                        content: SizedBox(
                          width: 320,
                          child: Text(
                            'Delete all ${items.length} generated images?',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(96, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await widget.galleryService.deleteAll();
                    }
                  },
                ),
            ],
          ),
          body: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No generated images yet',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Images you generate will appear here',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = (constraints.maxWidth ~/ 160)
                          .clamp(2, 5);
                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _GalleryThumbnail(
                            key: ValueKey(item.id),
                            item: item,
                            galleryService: widget.galleryService,
                            onTap: () => _viewImage(item),
                            onDelete: () => _deleteItem(item),
                          );
                        },
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _GalleryThumbnail extends StatefulWidget {
  final GalleryItem item;
  final GalleryService galleryService;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _GalleryThumbnail({
    super.key,
    required this.item,
    required this.galleryService,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_GalleryThumbnail> createState() => _GalleryThumbnailState();
}

class _GalleryThumbnailState extends State<_GalleryThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await widget.galleryService.loadImageBytes(
      widget.item.filePath,
    );
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _failed = bytes == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = widget.item.params.positivePrompt;
    return Semantics(
      label: 'Image${prompt.isNotEmpty ? ": $prompt" : ""}',
      hint: 'Double tap to view, long press to delete',
      child: GestureDetector(
        onTap: _failed ? null : widget.onTap,
        onLongPress: _failed ? null : widget.onDelete,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _bytes != null
              ? Image.memory(
                  _bytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Center(
                        child: Icon(
                          Icons.broken_image,
                          size: 28,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Center(
                    child: _failed
                        ? Icon(
                            Icons.broken_image,
                            size: 28,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatefulWidget {
  final List<GalleryItem> items;
  final int initialIndex;
  final void Function(GalleryItem item) onDelete;
  final GalleryService galleryService;
  final AppState appState;

  const _ImageViewer({
    required this.items,
    required this.initialIndex,
    required this.onDelete,
    required this.galleryService,
    required this.appState,
  });

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  final Map<String, Uint8List?> _bytesCache = {};
  final Map<String, Map<String, String>> _metaCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadAt(widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  GalleryItem get _currentItem => widget.items[_currentIndex];

  Future<void> _loadAt(int index) async {
    if (index < 0 || index >= widget.items.length) return;
    final item = widget.items[index];
    if (_bytesCache.containsKey(item.id)) return;
    _bytesCache[item.id] = null;
    final bytes = await widget.galleryService.loadImageBytes(item.filePath);
    if (!mounted) return;
    setState(() {
      _bytesCache[item.id] = bytes;
      if (bytes != null) {
        _metaCache[item.id] =
            widget.galleryService.readImageMetadataFromBytes(bytes);
      }
    });
  }

  bool get _hasEmbeddedConfig {
    final meta = _metaCache[_currentItem.id];
    if (meta == null) return false;
    return meta.containsKey('comfy_mobile') || meta.containsKey('prompt');
  }

  Future<void> _loadEmbeddedConfig() async {
    final meta = _metaCache[_currentItem.id];
    final mobileJson = meta?['comfy_mobile'];
    if (mobileJson == null) return;
    try {
      final data = jsonDecode(mobileJson) as Map<String, dynamic>;
      final params = GenerationParams.fromJson(
          data['params'] as Map<String, dynamic>? ?? {});
      final serverUrl = data['serverUrl'] as String? ?? '';
      if (mounted) {
        widget.appState.updateParams(params);
        if (serverUrl.isNotEmpty) {
          widget.appState.comfyService.updateBaseUrl(serverUrl);
        }
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Config loaded from image')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to read config from image')),
        );
      }
    }
  }

  Future<void> _saveToShared() async {
    final path =
        await widget.galleryService.saveToSharedLocation(_currentItem.id);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save image')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _currentItem.params;
    final profile = ArchitectureProfile.byId(s.profileId);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          if (_hasEmbeddedConfig)
            IconButton(
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: 'Load config from image',
              onPressed: _loadEmbeddedConfig,
            ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'Save to shared location',
            onPressed: _saveToShared,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => widget.onDelete(_currentItem),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                _loadAt(i - 1);
                _loadAt(i + 1);
              },
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final bytes = _bytesCache[item.id];
                if (bytes == null) {
                  if (!_bytesCache.containsKey(item.id)) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _loadAt(index));
                  }
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _metaChip(context, '${s.width}x${s.height}'),
                  const SizedBox(width: 8),
                  _metaChip(
                    context,
                    s.checkpoint.isNotEmpty
                        ? s.checkpoint.split('/').last.split('.').first
                        : 'No model',
                  ),
                  const SizedBox(width: 8),
                  _metaChip(context, profile.name),
                  const SizedBox(width: 8),
                  _metaChip(context, '${s.steps} steps'),
                  const SizedBox(width: 8),
                  _metaChip(context, 'CFG ${s.cfg}'),
                  const SizedBox(width: 8),
                  _metaChip(context, 'Seed ${s.seed}'),
                  if (s.positivePrompt.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _metaChip(
                      context,
                      s.positivePrompt.length > 35
                          ? '${s.positivePrompt.substring(0, 35)}...'
                          : s.positivePrompt,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: Colors.white,
        ),
      ),
    );
  }
}
