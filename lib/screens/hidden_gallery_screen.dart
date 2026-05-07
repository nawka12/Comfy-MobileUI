import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/config_service.dart';
import '../services/gallery_service.dart';
import 'home_screen.dart';

class HiddenGalleryScreen extends StatefulWidget {
  const HiddenGalleryScreen({super.key});

  @override
  State<HiddenGalleryScreen> createState() => _HiddenGalleryScreenState();
}

class _HiddenGalleryScreenState extends State<HiddenGalleryScreen> {
  AppState? _appState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = context.read<AppState>();
  }

  @override
  void dispose() {
    _appState?.setHiddenLibraryUnlocked(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.hiddenLibraryUnlocked) {
          return _LockGate(
            configService: state.configService,
            onUnlocked: () => state.setHiddenLibraryUnlocked(true),
          );
        }
        return _UnlockedView(state: state);
      },
    );
  }
}

class _LockGate extends StatefulWidget {
  final ConfigService configService;
  final VoidCallback onUnlocked;

  const _LockGate({required this.configService, required this.onUnlocked});

  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hasPassword = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPassword();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _checkPassword() async {
    final has = await widget.configService.hasHiddenPassword();
    if (mounted) setState(() { _hasPassword = has; _loading = false; });
  }

  Future<void> _submit() async {
    final pw = _password.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Password cannot be empty');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    if (_hasPassword) {
      final ok = await widget.configService.verifyHiddenPassword(pw);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() { _submitting = false; _error = 'Incorrect password'; });
        _password.clear();
      }
    } else {
      if (pw.length < 4) {
        setState(() {
          _submitting = false;
          _error = 'Password must be at least 4 characters';
        });
        return;
      }
      if (pw != _confirm.text) {
        setState(() {
          _submitting = false;
          _error = 'Passwords do not match';
        });
        return;
      }
      await widget.configService.setHiddenPassword(pw);
      if (!mounted) return;
      widget.onUnlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden Library')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hasPassword ? Icons.lock_outline : Icons.lock_open,
                        size: 56,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _hasPassword
                            ? 'Enter password'
                            : 'Set a password',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _hasPassword
                            ? 'Unlock the hidden library'
                            : 'This password protects your hidden library. If you forget it, the library can be cleared from Settings.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        onSubmitted: (_) {
                          if (_hasPassword) _submit();
                        },
                      ),
                      if (!_hasPassword) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirm,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: Text(_hasPassword ? 'Unlock' : 'Set password'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _UnlockedView extends StatelessWidget {
  final AppState state;
  const _UnlockedView({required this.state});

  Future<void> _addFromGallery(BuildContext context) async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => _GalleryPicker(galleryService: state.galleryService),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    for (final id in picked) {
      await state.galleryService.moveToHidden(id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved ${picked.length} to hidden library')),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final count = state.galleryService.hiddenItems.length;
    if (count == 0) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Hidden Library'),
        content: Text('Permanently delete all $count hidden images?'),
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
    if (confirm == true) {
      await state.galleryService.deleteAllHidden();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.galleryService,
      builder: (context, _) {
        final items = state.galleryService.hiddenItems;
        return Scaffold(
          appBar: AppBar(
            title: Text(items.isEmpty
                ? 'Hidden Library'
                : 'Hidden Library (${items.length})'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: 'Move from gallery',
                onPressed: () => _addFromGallery(context),
              ),
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Lock',
                onPressed: () => state.setHiddenLibraryUnlocked(false),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'delete_all':
                      _confirmDeleteAll(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete_all',
                    child: Text('Delete all'),
                  ),
                ],
              ),
            ],
          ),
          body: items.isEmpty
              ? _emptyState(context)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        (constraints.maxWidth ~/ 160).clamp(2, 5);
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
                        return _HiddenThumbnail(
                          key: ValueKey(item.id),
                          item: item,
                          galleryService: state.galleryService,
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing hidden yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + icon to move images here from the main gallery.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenThumbnail extends StatefulWidget {
  final GalleryItem item;
  final GalleryService galleryService;

  const _HiddenThumbnail({
    super.key,
    required this.item,
    required this.galleryService,
  });

  @override
  State<_HiddenThumbnail> createState() => _HiddenThumbnailState();
}

class _HiddenThumbnailState extends State<_HiddenThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes =
        await widget.galleryService.loadImageBytes(widget.item.filePath);
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _failed = bytes == null;
      });
    }
  }

  Future<void> _showOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View'),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('Restore to gallery'),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'view':
        _view();
      case 'restore':
        await widget.galleryService.restoreFromHidden(widget.item.id);
      case 'delete':
        _confirmDelete();
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Permanently delete this image?'),
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
    if (confirm == true) {
      await widget.galleryService.deleteHiddenItem(widget.item.id);
    }
  }

  void _view() {
    if (_bytes == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, _) => _HiddenImageViewer(
          imageBytes: _bytes!,
          item: widget.item,
          galleryService: widget.galleryService,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: _failed ? null : _view,
      onLongPress: _failed ? null : _showOptions,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover)
            : Container(
                color: theme.colorScheme.surfaceContainerLow,
                child: Center(
                  child: _failed
                      ? Icon(Icons.broken_image,
                          size: 28,
                          color: theme.colorScheme.onSurfaceVariant)
                      : const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              ),
      ),
    );
  }
}

class _HiddenImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final GalleryItem item;
  final GalleryService galleryService;

  const _HiddenImageViewer({
    required this.imageBytes,
    required this.item,
    required this.galleryService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: 'Restore to gallery',
            onPressed: () async {
              await galleryService.restoreFromHidden(item.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Image'),
                  content: const Text('Permanently delete this image?'),
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
              if (confirm == true) {
                await galleryService.deleteHiddenItem(item.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(child: Image.memory(imageBytes, fit: BoxFit.contain)),
      ),
    );
  }
}

class _GalleryPicker extends StatefulWidget {
  final GalleryService galleryService;

  const _GalleryPicker({required this.galleryService});

  @override
  State<_GalleryPicker> createState() => _GalleryPickerState();
}

class _GalleryPickerState extends State<_GalleryPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.galleryService,
      builder: (context, _) {
        final items = widget.galleryService.items;
        return Scaffold(
          appBar: AppBar(
            title: Text(_selected.isEmpty
                ? 'Move to hidden'
                : '${_selected.length} selected'),
            actions: [
              TextButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
                child: const Text('Move'),
              ),
            ],
          ),
          body: items.isEmpty
              ? const Center(child: Text('Gallery is empty'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        (constraints.maxWidth ~/ 160).clamp(2, 5);
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final selected = _selected.contains(item.id);
                        return _PickerThumbnail(
                          key: ValueKey(item.id),
                          item: item,
                          galleryService: widget.galleryService,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selected.remove(item.id);
                              } else {
                                _selected.add(item.id);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

class _PickerThumbnail extends StatefulWidget {
  final GalleryItem item;
  final GalleryService galleryService;
  final bool selected;
  final VoidCallback onTap;

  const _PickerThumbnail({
    super.key,
    required this.item,
    required this.galleryService,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PickerThumbnail> createState() => _PickerThumbnailState();
}

class _PickerThumbnailState extends State<_PickerThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes =
        await widget.galleryService.loadImageBytes(widget.item.filePath);
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _bytes != null
                ? Image.memory(_bytes!, fit: BoxFit.cover)
                : Container(color: theme.colorScheme.surfaceContainerLow),
          ),
          if (widget.selected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 3,
                ),
              ),
              alignment: Alignment.topRight,
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
