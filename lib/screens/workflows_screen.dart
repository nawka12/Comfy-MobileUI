import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/saved_workflow.dart';
import 'home_screen.dart';

class WorkflowsScreen extends StatelessWidget {
  const WorkflowsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Workflows'),
            actions: [
              IconButton(
                icon: const Icon(Icons.upload_file),
                tooltip: 'Load .json file',
                onPressed: () => _pickAndLoad(context, state),
              ),
            ],
          ),
          body: state.workflows.isEmpty
              ? _Empty(onLoad: () => _pickAndLoad(context, state))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: state.workflows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _WorkflowCard(
                    workflow: state.workflows[i],
                    isActive: state.workflows[i].id == state.activeWorkflowId,
                    onTap: () => state.setActiveWorkflow(state.workflows[i].id),
                    onRename: () => _rename(context, state, state.workflows[i]),
                    onDelete: () => _delete(context, state, state.workflows[i]),
                  ),
                ),
          floatingActionButton: state.workflows.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _pickAndLoad(context, state),
                  icon: const Icon(Icons.add),
                  label: const Text('Load workflow'),
                ),
        );
      },
    );
  }

  Future<void> _pickAndLoad(BuildContext context, AppState state) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    String? contents;
    if (file.bytes != null) {
      contents = _decodeUtf8(file.bytes!);
    } else if (file.path != null) {
      try {
        contents = await File(file.path!).readAsString();
      } catch (_) {}
    }

    if (!context.mounted) return;
    if (contents == null) {
      _snack(context, 'Could not read file');
      return;
    }

    if (state.validateApiWorkflow(contents) == null) {
      _snack(context,
          'Not API-format JSON. In ComfyUI: enable Dev mode, then "Save (API Format)".');
      return;
    }

    final defaultName = file.name
        .replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
    final name = await _promptName(context, defaultName);
    if (name == null || name.isEmpty || !context.mounted) return;

    final saved = await state.addWorkflow(name: name, contents: contents);
    if (!context.mounted) return;
    _snack(
      context,
      saved == null
          ? 'Failed to load workflow'
          : 'Loaded "${saved.name}"',
    );
  }

  Future<String?> _promptName(BuildContext context, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workflow name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(() => controller.dispose());
  }

  Future<void> _rename(
      BuildContext context, AppState state, SavedWorkflow w) async {
    final name = await _promptName(context, w.name);
    if (name == null || name.isEmpty) return;
    await state.renameWorkflow(w.id, name);
  }

  Future<void> _delete(
      BuildContext context, AppState state, SavedWorkflow w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete workflow'),
        content: Text('Delete "${w.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
    if (ok == true) await state.deleteWorkflow(w.id);
  }

  String? _decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  final SavedWorkflow workflow;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _WorkflowCard({
    required this.workflow,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputCount = _countInputs(workflow.json);
    return Card(
      margin: EdgeInsets.zero,
      color: isActive ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          isActive
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: isActive ? theme.colorScheme.primary : null,
        ),
        title: Text(
          workflow.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: isActive ? theme.colorScheme.onPrimaryContainer : null,
          ),
        ),
        subtitle: Text(
          '$inputCount nodes${workflow.values.isNotEmpty ? " · ${workflow.values.length} edits" : ""}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isActive
                ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Semantics(
          label: 'Workflow actions',
          button: true,
          child: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'rename':
                onRename();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        ),
      ),
    );
  }

  int _countInputs(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is Map) return raw.length;
    } catch (_) {}
    return 0;
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onLoad;
  const _Empty({required this.onLoad});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No workflows loaded',
                style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              'Load a ComfyUI "Save (API Format)" .json file to get a dynamic UI for any workflow.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.upload_file),
              label: const Text('Load .json'),
            ),
          ],
        ),
      ),
    );
  }
}
