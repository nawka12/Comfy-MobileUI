import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/architecture_profile.dart';
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
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
  String? _filterProfile;
  bool _sortNewestFirst = true;
  bool _showFilters = false;

  List<GalleryItem> get _filteredItems {
    var list = widget.galleryService.items.toList(growable: false);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((i) =>
        i.params.positivePrompt.toLowerCase().contains(q) ||
        i.params.checkpoint.toLowerCase().contains(q) ||
        i.params.negativePrompt.toLowerCase().contains(q)
      ).toList();
    }
    if (_filterProfile != null) {
      list = list.where((i) => i.params.profileId == _filterProfile).toList();
    }
    if (_sortNewestFirst) {
      list = list.reversed.toList();
    }
    return list;
  }

  Set<String> get _availableProfiles {
    return widget.galleryService.items.map((i) => i.params.profileId).toSet();
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectMode(String id) {
    setState(() {
      _selectMode = true;
      _selectedIds.add(id);
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected'),
        content: Text('Delete $count selected image${
          count == 1 ? '' : 's'}?'),
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
      for (final id in _selectedIds.toList()) {
        await widget.galleryService.deleteItem(id);
      }
      setState(() {
        _selectedIds.clear();
        _selectMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $count image${count == 1 ? '' : 's'}')),
        );
      }
    }
  }

  Future<void> _batchMoveToHidden() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    for (final id in _selectedIds.toList()) {
      await widget.galleryService.moveToHidden(id);
    }
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved $count image${count == 1 ? '' : 's'} to hidden library')),
      );
    }
  }

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
        final allItems = widget.galleryService.items;
        final filtered = _filteredItems;
        final totalCount = allItems.length;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectMode
                  ? '${_selectedIds.length} selected'
                  : filtered.length < totalCount
                      ? 'Gallery ($filtered of $totalCount)'
                      : totalCount > 0
                          ? 'Gallery ($totalCount)'
                          : 'Gallery',
            ),
            leading: _selectMode
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _toggleSelectMode,
                    tooltip: 'Exit selection',
                  )
                : null,
            actions: [
              if (_selectMode) ...[
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete selected',
                  onPressed: _selectedIds.isNotEmpty ? _batchDelete : null,
                ),
                IconButton(
                  icon: const Icon(Icons.lock_outline),
                  tooltip: 'Move to hidden library',
                  onPressed: _selectedIds.isNotEmpty ? _batchMoveToHidden : null,
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Toggle filters',
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                ),
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
                if (allItems.isNotEmpty)
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
                              'Delete all $totalCount generated images?',
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
            ],
          ),
          body: allItems.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    if (_showFilters) _buildFilterBar(context),
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildNoMatchState()
                          : RefreshIndicator(
                              onRefresh: () async => setState(() {}),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final crossAxisCount =
                                      (constraints.maxWidth ~/ 160).clamp(2, 5);
                                  return GridView.builder(
                                    padding: const EdgeInsets.all(12),
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final item = filtered[index];
                                      final isSelected =
                                          _selectedIds.contains(item.id);
                                      return _GalleryThumbnail(
                                        key: ValueKey(item.id),
                                        item: item,
                                        galleryService: widget.galleryService,
                                        selectMode: _selectMode,
                                        isSelected: isSelected,
                                        onTap: _selectMode
                                            ? () => _toggleItem(item.id)
                                            : () => _viewImage(item),
                                        onLongPress: _selectMode
                                            ? null
                                            : () => _enterSelectMode(item.id),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No generated images yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Images you generate will appear here',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatchState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No images match your filters',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => setState(() {
              _searchQuery = '';
              _filterProfile = null;
            }),
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = _availableProfiles;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        )),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by prompt or model...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filterProfile == null,
                  onSelected: (_) => setState(() => _filterProfile = null),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                ...profiles.map((p) {
                  final arch = ArchitectureProfile.byId(p);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(arch.name),
                      selected: _filterProfile == p,
                      onSelected: (_) => setState(() {
                        _filterProfile = _filterProfile == p ? null : p;
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(
                    _sortNewestFirst ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 18,
                  ),
                  tooltip: _sortNewestFirst ? 'Newest first' : 'Oldest first',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _GalleryThumbnail extends StatefulWidget {
  final GalleryItem item;
  final GalleryService galleryService;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectMode;
  final bool isSelected;

  const _GalleryThumbnail({
    super.key,
    required this.item,
    required this.galleryService,
    required this.onTap,
    this.onLongPress,
    this.selectMode = false,
    this.isSelected = false,
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
      hint: widget.selectMode
          ? 'Tap to select'
          : 'Double tap to view, long press to select',
      child: GestureDetector(
        onTap: _failed ? null : widget.onTap,
        onLongPress: (_failed || widget.selectMode) ? null : widget.onLongPress,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _bytes != null
                  ? Image.memory(
                      _bytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: theme.colorScheme.surfaceContainerLow,
                          child: const Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 28,
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Center(
                        child: _failed
                            ? const Icon(
                                Icons.broken_image,
                                size: 28,
                              )
                            : const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                      ),
                    ),
            ),
            if (widget.selectMode || widget.isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surface.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    widget.isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: widget.isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (widget.isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
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
    });
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
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: 'Send to Generate',
            onPressed: () {
              widget.appState.updateParams(_currentItem.params);
              widget.appState.requestTab(0);
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
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
