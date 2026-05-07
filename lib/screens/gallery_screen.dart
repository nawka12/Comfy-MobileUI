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
    final bytes = await widget.galleryService.loadImageBytes(item.filePath);
    if (bytes == null) return;
    if (!mounted) return;
    final appState = context.read<AppState>();
    final metadata = widget.galleryService.readImageMetadataFromBytes(bytes);
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _ImageViewer(
          imageBytes: bytes,
          item: item,
          metadata: metadata,
          galleryService: widget.galleryService,
          appState: appState,
          onDelete: () {
            Navigator.of(context).pop();
            _deleteItem(item);
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
  final Uint8List imageBytes;
  final GalleryItem item;
  final Map<String, String> metadata;
  final VoidCallback onDelete;
  final GalleryService galleryService;
  final AppState appState;

  const _ImageViewer({
    required this.imageBytes,
    required this.item,
    this.metadata = const {},
    required this.onDelete,
    required this.galleryService,
    required this.appState,
  });

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  bool _hasEmbeddedConfig = false;

  @override
  void initState() {
    super.initState();
    _hasEmbeddedConfig =
        widget.metadata.containsKey('comfy_mobile') ||
        widget.metadata.containsKey('prompt');
  }

  Future<void> _loadEmbeddedConfig() async {
    final mobileJson = widget.metadata['comfy_mobile'];
    if (mobileJson != null) {
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
  }

  Future<void> _saveToShared() async {
    final path = await widget.galleryService.saveToSharedLocation(widget.item.id);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save image')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.item.params;
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
            onPressed: widget.onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
              ),
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
