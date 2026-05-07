import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/architecture_profile.dart';
import '../models/config_preset.dart';
import '../models/workflow.dart';
import 'home_screen.dart';

Future<bool> _saveJsonFile({
  required String fileName,
  required String content,
  required String dialogTitle,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(content));
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: bytes,
  );
  if (path == null) return false;
  // On desktop platforms file_picker returns the path without writing;
  // ensure the file actually exists with the expected content.
  try {
    final file = File(path);
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes);
    }
  } catch (_) {
    // dart:io may not be available on every platform — file_picker
    // already wrote the bytes on mobile, so this is best-effort.
  }
  return true;
}

Future<String?> _readJsonFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if (file.bytes != null) {
    try {
      return utf8.decode(file.bytes!);
    } catch (_) {
      return null;
    }
  }
  if (file.path != null) {
    try {
      return await File(file.path!).readAsString();
    } catch (_) {
      return null;
    }
  }
  return null;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCard(
                children: [
                  _buildSectionTitle(context, 'Server', Icons.wifi),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.link,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                    title: const Text('ComfyUI URL'),
                    subtitle: Text(state.comfyService.baseUrl,
                        style: const TextStyle(fontFamily: 'monospace')),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _editServerUrl(state),
                  ),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (state.connected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        state.connected
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 20,
                        color: state.connected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    title: Text(
                        state.connected ? 'Connected' : 'Disconnected'),
                    subtitle: Text(state.connected
                        ? '${state.availableModels.length} models available'
                        : 'Tap to reconnect'),
                    onTap: () => state.checkConnection(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildCard(
                children: [
                  _buildSectionTitle(context, 'Config', Icons.settings),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.save,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer),
                    ),
                    title: const Text('Save Current Config'),
                    subtitle: const Text('Persist settings for next session'),
                    onTap: () {
                      state.saveConfig();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Config saved')),
                      );
                    },
                  ),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.upload_file,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onTertiaryContainer),
                    ),
                    title: const Text('Export Config'),
                    subtitle: const Text('Save as .json file'),
                    onTap: () => _exportConfig(state),
                  ),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.download,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onTertiaryContainer),
                    ),
                    title: const Text('Import Config'),
                    subtitle: const Text('Load from .json file'),
                    onTap: () => _importConfig(state),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildCard(
                children: [
                  _buildSectionTitle(context, 'Defaults', Icons.toggle_off_outlined),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.save_alt,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                    title: const Text('Auto-save on Generate'),
                    subtitle: const Text('Save settings each time you generate'),
                    value: state.autoSave,
                    onChanged: (v) => state.setAutoSave(v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PresetsCard(),
              const SizedBox(height: 12),
              _buildPrivacyCard(context, state),
              const SizedBox(height: 12),
              _buildCard(
                children: [
                  _buildSectionTitle(context, 'About', Icons.info_outline),
                  const SizedBox(height: 8),
                  const ListTile(
                    title: Text('Comfy Mobile UI'),
                    subtitle: Text('Version 2.0.0'),
                  ),
                  ListTile(
                    title: const Text('Supported Architectures'),
                    subtitle: Text(
                      ArchitectureProfile.all.map((p) => p.name).join(', '),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrivacyCard(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    return _buildCard(
      children: [
        _buildSectionTitle(context, 'Privacy', Icons.shield_outlined),
        const SizedBox(height: 8),
        if (Platform.isAndroid)
          SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.blur_on,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ),
            title: const Text('Blur in app switcher'),
            subtitle: const Text(
                'Redact the app preview in recents and block screenshots'),
            value: state.secureWindow,
            onChanged: (v) => state.setSecureWindow(v),
          ),
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.lock_outline,
                size: 20, color: theme.colorScheme.onSecondaryContainer),
          ),
          title: const Text('Hidden Library'),
          subtitle: const Text('Password-protected gallery'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openHiddenLibraryManager(context, state),
        ),
      ],
    );
  }

  Future<void> _openHiddenLibraryManager(
      BuildContext context, AppState state) async {
    final hasPassword = await state.configService.hasHiddenPassword();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(hasPassword ? Icons.lock_reset : Icons.lock_outline),
              title: Text(hasPassword ? 'Change password' : 'Set password'),
              onTap: () {
                Navigator.pop(ctx);
                _changePassword(state, requireExisting: hasPassword);
              },
            ),
            if (hasPassword)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Clear hidden library'),
                subtitle: const Text(
                    'Remove password and permanently delete all hidden images'),
                onTap: () {
                  Navigator.pop(ctx);
                  _clearHiddenLibrary(state);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword(AppState state,
      {required bool requireExisting}) async {
    final result = await showDialog<_PasswordChange>(
      context: context,
      builder: (ctx) =>
          _PasswordDialog(requireExisting: requireExisting),
    );
    if (result == null || !mounted) return;
    final cfg = state.configService;
    if (requireExisting) {
      final ok = await cfg.verifyHiddenPassword(result.current!);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current password is incorrect')),
        );
        return;
      }
    }
    await cfg.setHiddenPassword(result.next);
    state.setHiddenLibraryUnlocked(false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(requireExisting
            ? 'Password changed'
            : 'Hidden library password set'),
      ),
    );
  }

  Future<void> _clearHiddenLibrary(AppState state) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Hidden Library'),
        content: const Text(
            'This permanently deletes all hidden images and removes the password. This cannot be undone.'),
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
    if (confirm != true || !mounted) return;
    await state.galleryService.deleteAllHidden();
    await state.configService.clearHiddenPassword();
    state.setHiddenLibraryUnlocked(false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hidden library cleared')),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  void _editServerUrl(AppState state) {
    final controller = TextEditingController(text: state.comfyService.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ComfyUI URL',
            hintText: 'http://192.168.1.100:8188',
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
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
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save & Connect')),
        ],
      ),
    ).then((result) {
      controller.dispose();
      if (result != null && result.isNotEmpty) {
        state.comfyService.updateBaseUrl(result);
        state.configService.saveServerUrl(result);
        state.checkConnection();
      }
    });
  }

  Future<void> _exportConfig(AppState state) async {
    final config = AppConfig(
      serverUrl: state.comfyService.baseUrl,
      params: state.params,
    );
    final saved = await _saveJsonFile(
      fileName: 'comfy_mobile_config.json',
      content: config.exportJson(),
      dialogTitle: 'Save config',
    );
    if (!mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config saved')),
      );
    }
  }

  Future<void> _importConfig(AppState state) async {
    final contents = await _readJsonFile();
    if (!mounted) return;
    if (contents == null) return;
    final config = AppConfig.importJson(contents);
    if (config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid config JSON')),
      );
      return;
    }
    state.comfyService.updateBaseUrl(config.serverUrl);
    state.updateParams(config.params);
    await state.configService.saveServerUrl(config.serverUrl);
    await state.configService.saveParams(config.params);
    await state.checkConnection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Config imported successfully')),
    );
  }
}

class _PresetsCard extends StatefulWidget {
  @override
  State<_PresetsCard> createState() => _PresetsCardState();
}

class _PresetsCardState extends State<_PresetsCard> {
  List<ConfigPreset> _presets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final presets = await state.loadPresets();
    if (mounted) setState(() { _presets = presets; _loading = false; });
  }

  Future<void> _saveCurrent() async {
    final state = context.read<AppState>();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Config Preset'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Preset name',
            hintText: 'e.g. Portrait style',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await state.savePreset(name);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preset "$name" saved')),
        );
      }
    }
  }

  Future<void> _loadPreset(ConfigPreset preset) async {
    final state = context.read<AppState>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load Preset'),
        content: Text('Apply "${preset.name}" settings?'),
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
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await state.applyPreset(preset);
      await state.checkConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preset "${preset.name}" applied')),
        );
      }
    }
  }

  Future<void> _renamePreset(ConfigPreset preset) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: preset.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Preset'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Preset name'),
          autofocus: true,
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
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await state.renamePreset(preset.id, name);
      await _load();
    }
  }

  Future<void> _deletePreset(ConfigPreset preset) async {
    final state = context.read<AppState>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Preset'),
        content: Text('Delete "${preset.name}"?'),
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
    if (confirm == true) {
      await state.deletePreset(preset.id);
      await _load();
    }
  }

  Future<void> _exportPreset(ConfigPreset preset) async {
    final json = await context
        .read<AppState>()
        .configService
        .exportPresetJson(preset);
    final safe = preset.name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    final saved = await _saveJsonFile(
      fileName: 'preset_$safe.json',
      content: json,
      dialogTitle: 'Save preset',
    );
    if (!mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "${preset.name}" saved')),
      );
    }
  }

  Future<void> _importPreset() async {
    final configService = context.read<AppState>().configService;
    final contents = await _readJsonFile();
    if (!mounted) return;
    if (contents == null) return;
    final preset = await configService.importPresetJson(contents);
    if (!mounted) return;
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid preset JSON')),
      );
      return;
    }
    await configService.savePreset(preset.name, preset.params, preset.serverUrl);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preset imported')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.bookmark, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Presets',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: 'Save current as preset',
                    onPressed: _saveCurrent,
                    style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_download, size: 20),
                    tooltip: 'Import preset',
                    onPressed: _importPreset,
                    style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_presets.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text('No saved presets',
                  style: TextStyle(color: Colors.grey)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _presets.length,
                itemBuilder: (context, index) {
                  final preset = _presets[index];
                  final arch = ArchitectureProfile.byId(preset.params.profileId);
                  return ListTile(
                    dense: true,
                    title: Text(preset.name, style: theme.textTheme.bodyMedium),
                    subtitle: Text(
                      '${arch.name} · ${preset.params.checkpoint.split('/').last.split('.').first}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow, size: 20),
                          tooltip: 'Apply',
                          onPressed: () => _loadPreset(preset),
                          style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (v) {
                            switch (v) {
                              case 'rename': _renamePreset(preset);
                              case 'export': _exportPreset(preset);
                              case 'delete': _deletePreset(preset);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'rename', child: Text('Rename')),
                            const PopupMenuItem(value: 'export', child: Text('Export')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PasswordChange {
  final String? current;
  final String next;
  _PasswordChange({this.current, required this.next});
}

class _PasswordDialog extends StatefulWidget {
  final bool requireExisting;
  const _PasswordDialog({required this.requireExisting});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.requireExisting && _current.text.isEmpty) {
      setState(() => _error = 'Enter current password');
      return;
    }
    if (_next.text.length < 4) {
      setState(() => _error = 'New password must be at least 4 characters');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    Navigator.of(context).pop(_PasswordChange(
      current: widget.requireExisting ? _current.text : null,
      next: _next.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.requireExisting ? 'Change password' : 'Set password'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.requireExisting) ...[
              TextField(
                controller: _current,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current password'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _next,
              obscureText: true,
              autofocus: !widget.requireExisting,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
