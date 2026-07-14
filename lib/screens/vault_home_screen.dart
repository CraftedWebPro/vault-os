import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../controllers/vault_app_controller.dart';
import '../models/preview_payload.dart';
import '../models/vault_entry.dart';
import 'settings_screen.dart';
import '../theme/vault_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/vault_mark.dart';
import 'vault_setup_details_screen.dart';

class VaultHomeScreen extends StatefulWidget {
  const VaultHomeScreen({
    super.key,
    required this.controller,
  });

  final VaultAppController controller;

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> {
  _VaultFilter _filter = _VaultFilter.all;
  VaultEntry? _selectedEntry;
  Future<PreviewPayload>? _previewFuture;
  bool _isDragging = false;
  _CompactPane _compactPane = _CompactPane.files;

  VaultAppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant VaultHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelection();
  }

  void _syncSelection() {
    final filtered = _filteredEntries;
    if (filtered.isEmpty) {
      _selectedEntry = null;
      _previewFuture = null;
      return;
    }

    final current = _selectedEntry;
    if (current != null) {
      final match = filtered.where((entry) => entry.id == current.id);
      if (match.isNotEmpty) {
        _selectedEntry = match.first;
        return;
      }
    }

    _selectEntry(filtered.first, loadPreview: false);
  }

  List<VaultEntry> get _filteredEntries {
    final entries = _controller.entries;
    switch (_filter) {
      case _VaultFilter.all:
        return entries;
      case _VaultFilter.images:
        return entries.where((entry) => _kindFor(entry) == _EntryKind.image).toList(growable: false);
      case _VaultFilter.videos:
        return entries.where((entry) => _kindFor(entry) == _EntryKind.video).toList(growable: false);
      case _VaultFilter.files:
        return entries.where((entry) => _kindFor(entry) == _EntryKind.file).toList(growable: false);
      case _VaultFilter.archives:
        return entries.where((entry) => _kindFor(entry) == _EntryKind.archive).toList(growable: false);
      case _VaultFilter.other:
        return entries.where((entry) => _kindFor(entry) == _EntryKind.other).toList(growable: false);
    }
  }

  int get _totalBytes => _controller.entries.fold<int>(0, (sum, entry) => sum + entry.originalSize);

  void _selectEntry(VaultEntry entry, {bool loadPreview = true}) {
    setState(() {
      _selectedEntry = entry;
      if (loadPreview) {
        _previewFuture = _controller.previewEntry(entry);
      }
    });
  }

  Future<void> _importDroppedFiles(List<String> files) async {
    await _controller.importFilesFromPaths(files);
    if (!mounted) {
      return;
    }
    setState(() {
      _syncSelection();
    });
  }

  Widget _buildLibraryPane({bool compactMode = false}) {
    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Library', style: VaultTheme.heading),
                  const SizedBox(height: 12),
                  for (final filter in _VaultFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FilterTile(
                        filter: filter,
                        selected: _filter == filter,
                        count: _countForFilter(filter),
                        onTap: () {
                          setState(() {
                            _filter = filter;
                            _syncSelection();
                            if (compactMode) {
                              _compactPane = _CompactPane.files;
                            }
                          });
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: VaultTheme.surfaceRaised,
                      borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
                      border: Border.all(color: VaultTheme.border),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Drop Zone', style: VaultTheme.heading),
                        SizedBox(height: 6),
                        Text(
                          'Drag files anywhere over the vault view to import them directly.',
                          style: VaultTheme.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilesPane(
    VaultAppController controller,
    List<VaultEntry> entries,
    VaultEntry? selectedEntry,
    {bool compactMode = false,}
  ) {
    return SectionCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: <Widget>[
                Text(_filter.label, style: VaultTheme.heading),
                const SizedBox(width: 10),
                Text('${entries.length} items', style: VaultTheme.caption),
                const Spacer(),
                Icon(
                  Icons.drag_indicator_rounded,
                  color: _isDragging ? VaultTheme.brass : VaultTheme.textMuted,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: VaultTheme.border),
          Expanded(
            child: entries.isEmpty
                ? const _EmptyVault()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: VaultTheme.border),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final selected = selectedEntry?.id == entry.id;
                      return _VaultRow(
                        entry: entry,
                        selected: selected,
                        busy: controller.isBusy,
                        onTap: () {
                          _selectEntry(entry);
                          if (compactMode) {
                            setState(() {
                              _compactPane = _CompactPane.details;
                            });
                          }
                        },
                        onOpen: () => _showPreviewDialog(context, entry),
                        onDelete: () async {
                          await controller.deleteEntry(entry);
                          if (!mounted) {
                            return;
                          }
                          setState(_syncSelection);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPane(
    VaultAppController controller,
    VaultEntry? selectedEntry, {
    bool showInlinePreview = true,
  }) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: selectedEntry == null
          ? const _NothingSelected()
          : _DetailsPane(
              entry: selectedEntry,
              previewFuture: _previewFuture ?? controller.previewEntry(selectedEntry),
              onOpenPreview: () => _showPreviewDialog(context, selectedEntry),
              showInlinePreview: showInlinePreview,
            ),
    );
  }

  Widget _buildCompactToggleBar(VaultEntry? selectedEntry) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _CompactToggleButton(
            icon: Icons.tune_rounded,
            label: 'Library',
            selected: _compactPane == _CompactPane.library,
            onTap: () {
              setState(() {
                _compactPane = _CompactPane.library;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactToggleButton(
            icon: Icons.folder_copy_outlined,
            label: _filter.label,
            selected: _compactPane == _CompactPane.files,
            onTap: () {
              setState(() {
                _compactPane = _CompactPane.files;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactToggleButton(
            icon: Icons.info_outline_rounded,
            label: selectedEntry == null ? 'Details' : 'Selected',
            selected: _compactPane == _CompactPane.details,
            onTap: () {
              setState(() {
                _compactPane = _CompactPane.details;
              });
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final entries = _filteredEntries;
    final config = controller.config;
    final selectedEntry = _selectedEntry;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: const Row(
          children: <Widget>[
            VaultMark(size: 24),
            SizedBox(width: 10),
            Text('Vault OS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: <Widget>[
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () => VaultSetupDetailsScreen.open(
                      context,
                      controller: controller,
                      allowReuseCurrentSecurity: true,
                    ),
            icon: const Icon(Icons.add_box_outlined, size: 15),
            label: const Text('Create Vault'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: controller.isBusy ? null : () async {
              await controller.refreshEntries();
              if (!mounted) {
                return;
              }
              setState(_syncSelection);
            },
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Refresh'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: controller.isBusy ? null : controller.importFiles,
            icon: const Icon(Icons.add_circle_outline, size: 15),
            label: Text(controller.isBusy ? 'Working...' : 'Add Files'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: controller.isBusy ? null : controller.revealVaultLocation,
            icon: const Icon(Icons.folder_open_outlined, size: 15),
            label: const Text('Reveal Vault'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: controller.isBusy ? null : controller.lock,
            icon: const Icon(Icons.lock_outline, size: 15),
            label: const Text('Lock'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(SettingsScreen.routeName),
            icon: const Icon(Icons.tune_outlined, size: 15),
            label: const Text('Settings'),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          setState(() => _isDragging = false);
          await _importDroppedFiles(details.files.map((file) => file.path).toList(growable: false));
        },
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Flexible(
                                        child: Text(
                                          config?.vaultName ?? 'Unknown vault',
                                          style: VaultTheme.display.copyWith(fontSize: 22),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      StatusPill(
                                        label: '${_controller.entries.length} FILE${_controller.entries.length == 1 ? '' : 'S'}',
                                        tone: PillTone.brass,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    controller.statusMessage ??
                                        'Explorer mode is live. Click a file, drag things in, or reveal the workspace and let the chaos happen there.',
                                    style: VaultTheme.body,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            FilledButton.icon(
                              onPressed: controller.isBusy ? null : controller.importFiles,
                              icon: const Icon(Icons.upload_file_outlined, size: 16),
                              label: const Text('Import Files'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            _InfoChip(
                              icon: Icons.inventory_2_outlined,
                              label: 'Vault files',
                              value: '${_controller.entries.length}',
                            ),
                            _InfoChip(
                              icon: Icons.data_usage_outlined,
                              label: 'Encrypted load',
                              value: _formatBytes(_totalBytes),
                            ),
                            _InfoChip(
                              icon: Icons.save_outlined,
                              label: 'Selected',
                              value: selectedEntry == null ? 'Nothing selected' : _formatBytes(selectedEntry.originalSize),
                            ),
                            _InfoChip(
                              icon: Icons.storage_outlined,
                              label: 'Drive',
                              value: _driveLabel(config?.vaultDirectory),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;

                        if (width >= 1400) {
                          return Row(
                            children: <Widget>[
                              SizedBox(
                                width: 220,
                                child: _buildLibraryPane(),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: _buildFilesPane(controller, entries, selectedEntry),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 360,
                                child: _buildDetailsPane(controller, selectedEntry),
                              ),
                            ],
                          );
                        }

                        if (width >= 1180) {
                          return Row(
                            children: <Widget>[
                              SizedBox(
                                width: 220,
                                child: _buildLibraryPane(),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  children: <Widget>[
                                    Expanded(
                                      child: _buildFilesPane(controller, entries, selectedEntry),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 220,
                                      child: _buildDetailsPane(
                                        controller,
                                        selectedEntry,
                                        showInlinePreview: false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: <Widget>[
                            const SizedBox(height: 16),
                            _buildCompactToggleBar(selectedEntry),
                            const SizedBox(height: 16),
                            Expanded(
                              child: switch (_compactPane) {
                                _CompactPane.library => _buildLibraryPane(compactMode: true),
                                _CompactPane.files => _buildFilesPane(
                                  controller,
                                  entries,
                                  selectedEntry,
                                  compactMode: true,
                                ),
                                _CompactPane.details => _buildDetailsPane(
                                  controller,
                                  selectedEntry,
                                  showInlinePreview: false,
                                ),
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_isDragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(VaultTheme.radius),
                      border: Border.all(color: VaultTheme.brass, width: 2),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.file_upload_outlined, size: 48, color: VaultTheme.brassBright),
                          SizedBox(height: 12),
                          Text('Drop files to import into the vault', style: VaultTheme.heading),
                          SizedBox(height: 6),
                          Text('They will be encrypted immediately after the drop.', style: VaultTheme.body),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _countForFilter(_VaultFilter filter) {
    switch (filter) {
      case _VaultFilter.all:
        return _controller.entries.length;
      case _VaultFilter.images:
        return _controller.entries.where((entry) => _kindFor(entry) == _EntryKind.image).length;
      case _VaultFilter.videos:
        return _controller.entries.where((entry) => _kindFor(entry) == _EntryKind.video).length;
      case _VaultFilter.files:
        return _controller.entries.where((entry) => _kindFor(entry) == _EntryKind.file).length;
      case _VaultFilter.archives:
        return _controller.entries.where((entry) => _kindFor(entry) == _EntryKind.archive).length;
      case _VaultFilter.other:
        return _controller.entries.where((entry) => _kindFor(entry) == _EntryKind.other).length;
    }
  }

  Future<void> _showPreviewDialog(BuildContext context, VaultEntry entry) async {
    final payload = await _controller.previewEntry(entry);
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: VaultTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VaultTheme.radius),
            side: const BorderSide(color: VaultTheme.border),
          ),
          title: Text(payload.name, style: VaultTheme.heading),
          content: SizedBox(
            width: 700,
            child: _PreviewBody(payload: payload),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

enum _VaultFilter {
  all('All files', Icons.grid_view_rounded),
  images('Images', Icons.image_outlined),
  videos('Videos', Icons.movie_outlined),
  files('Files', Icons.description_outlined),
  archives('Archives', Icons.folder_zip_outlined),
  other('Other', Icons.insert_drive_file_outlined);

  const _VaultFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _CompactPane { library, files, details }

enum _EntryKind { image, video, file, archive, other }

_EntryKind _kindFor(VaultEntry entry) {
  final extension = path.extension(entry.displayName).toLowerCase();
  if (const <String>{'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(extension)) {
    return _EntryKind.image;
  }
  if (const <String>{'.mp4', '.webm', '.mov', '.mkv', '.avi', '.wmv', '.m4v'}.contains(extension)) {
    return _EntryKind.video;
  }
  if (const <String>{
    '.txt',
    '.md',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.log',
    '.pdf',
    '.doc',
    '.docx',
    '.rtf',
    '.ppt',
    '.pptx',
    '.xls',
    '.xlsx',
  }.contains(extension)) {
    return _EntryKind.file;
  }
  if (const <String>{'.zip', '.rar', '.7z', '.tar', '.gz'}.contains(extension)) {
    return _EntryKind.archive;
  }
  return _EntryKind.other;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _driveLabel(String? vaultDirectory) {
  if (vaultDirectory == null || vaultDirectory.isEmpty) {
    return 'Unknown';
  }
  final root = path.rootPrefix(vaultDirectory);
  return root.isEmpty ? vaultDirectory : root;
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VaultTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
        border: Border.all(color: VaultTheme.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: VaultTheme.brass),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: VaultTheme.caption),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: VaultTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.filter,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final _VaultFilter filter;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? VaultTheme.brass.withValues(alpha: 0.12) : VaultTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
          border: Border.all(
            color: selected ? VaultTheme.brass.withValues(alpha: 0.5) : VaultTheme.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(filter.icon, size: 16, color: selected ? VaultTheme.brassBright : VaultTheme.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                filter.label,
                style: TextStyle(
                  color: selected ? VaultTheme.textPrimary : VaultTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            Text('$count', style: VaultTheme.caption),
          ],
        ),
      ),
    );
  }
}

class _CompactToggleButton extends StatelessWidget {
  const _CompactToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 16,
        color: selected ? VaultTheme.brassBright : VaultTheme.textSecondary,
      ),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? VaultTheme.brass.withValues(alpha: 0.12) : null,
        side: BorderSide(
          color: selected ? VaultTheme.brass.withValues(alpha: 0.45) : VaultTheme.border,
        ),
        foregroundColor: selected ? VaultTheme.textPrimary : VaultTheme.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }
}

class _VaultRow extends StatelessWidget {
  const _VaultRow({
    required this.entry,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onOpen,
    required this.onDelete,
  });

  final VaultEntry entry;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  IconData get _icon {
    switch (_kindFor(entry)) {
      case _EntryKind.image:
        return Icons.image_outlined;
      case _EntryKind.video:
        return Icons.movie_outlined;
      case _EntryKind.file:
        return Icons.description_outlined;
      case _EntryKind.archive:
        return Icons.folder_zip_outlined;
      case _EntryKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? VaultTheme.brass.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
        ),
        child: Row(
          children: <Widget>[
            Icon(_icon, size: 18, color: selected ? VaultTheme.brassBright : VaultTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.displayName,
                    style: const TextStyle(fontSize: 13.5, color: VaultTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.relativePath}  •  ${_formatBytes(entry.originalSize)}',
                    style: VaultTheme.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onOpen,
              icon: const Icon(Icons.visibility_outlined, size: 17),
              tooltip: 'Preview',
              color: VaultTheme.textSecondary,
            ),
            IconButton(
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline, size: 17),
              tooltip: 'Delete',
              color: VaultTheme.danger,
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.touch_app_outlined, size: 32, color: VaultTheme.textMuted),
          SizedBox(height: 12),
          Text('Pick a file', style: VaultTheme.heading),
          SizedBox(height: 6),
          Text(
            'Select something from the list to inspect details and preview it here.',
            textAlign: TextAlign.center,
            style: VaultTheme.body,
          ),
        ],
      ),
    );
  }
}

class _DetailsPane extends StatelessWidget {
  const _DetailsPane({
    required this.entry,
    required this.previewFuture,
    required this.onOpenPreview,
    required this.showInlinePreview,
  });

  final VaultEntry entry;
  final Future<PreviewPayload> previewFuture;
  final VoidCallback onOpenPreview;
  final bool showInlinePreview;

  @override
  Widget build(BuildContext context) {
    if (!showInlinePreview) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Details', style: VaultTheme.heading),
            const SizedBox(height: 14),
            _DetailRow(label: 'Name', value: entry.displayName),
            _DetailRow(label: 'Workspace path', value: entry.relativePath),
            _DetailRow(label: 'Size', value: _formatBytes(entry.originalSize)),
            _DetailRow(label: 'Added', value: entry.createdAtIso.replaceFirst('T', ' ').split('.').first),
            _DetailRow(label: 'Type', value: path.extension(entry.displayName).replaceFirst('.', '').toUpperCase().ifEmpty('Unknown')),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpenPreview,
                icon: const Icon(Icons.open_in_new_outlined, size: 16),
                label: const Text('Open preview'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Details', style: VaultTheme.heading),
        const SizedBox(height: 14),
        _DetailRow(label: 'Name', value: entry.displayName),
        _DetailRow(label: 'Workspace path', value: entry.relativePath),
        _DetailRow(label: 'Size', value: _formatBytes(entry.originalSize)),
        _DetailRow(label: 'Added', value: entry.createdAtIso.replaceFirst('T', ' ').split('.').first),
        _DetailRow(label: 'Type', value: path.extension(entry.displayName).replaceFirst('.', '').toUpperCase().ifEmpty('Unknown')),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onOpenPreview,
            icon: const Icon(Icons.open_in_new_outlined, size: 16),
            label: const Text('Open preview'),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VaultTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
              border: Border.all(color: VaultTheme.border),
            ),
            child: FutureBuilder<PreviewPayload>(
              future: previewFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const Center(
                    child: Text(
                      'Preview unavailable for this file right now.',
                      textAlign: TextAlign.center,
                      style: VaultTheme.body,
                    ),
                  );
                }
                return _InlinePreview(payload: snapshot.data!);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: VaultTheme.caption),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(
              color: VaultTheme.textPrimary,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.inventory_2_outlined, size: 32, color: VaultTheme.textMuted),
          SizedBox(height: 12),
          Text('Nothing in here yet', style: VaultTheme.heading),
          SizedBox(height: 6),
          Text(
            'Import files with the button above or just drag them onto the vault window.',
            textAlign: TextAlign.center,
            style: VaultTheme.body,
          ),
        ],
      ),
    );
  }
}

class _InlinePreview extends StatelessWidget {
  const _InlinePreview({
    required this.payload,
  });

  final PreviewPayload payload;

  @override
  Widget build(BuildContext context) {
    switch (payload.kind) {
      case PreviewKind.image:
        return SingleChildScrollView(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
            child: Image.memory(Uint8List.fromList(payload.bytes)),
          ),
        );
      case PreviewKind.text:
        return SingleChildScrollView(
          child: SelectableText(
            payload.text ?? '',
            style: const TextStyle(color: VaultTheme.textPrimary, fontSize: 12.5),
          ),
        );
      case PreviewKind.binary:
        return Center(
          child: Text(
            'Binary file\n${payload.bytes.length} bytes loaded for preview.',
            textAlign: TextAlign.center,
            style: VaultTheme.body,
          ),
        );
    }
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.payload,
  });

  final PreviewPayload payload;

  @override
  Widget build(BuildContext context) {
    switch (payload.kind) {
      case PreviewKind.image:
        return SingleChildScrollView(
          child: Image.memory(Uint8List.fromList(payload.bytes)),
        );
      case PreviewKind.text:
        return SingleChildScrollView(
          child: SelectableText(payload.text ?? ''),
        );
      case PreviewKind.binary:
        return Text(
          'No preview for this one.\n\nBytes in memory: ${payload.bytes.length}',
          style: VaultTheme.body,
        );
    }
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
