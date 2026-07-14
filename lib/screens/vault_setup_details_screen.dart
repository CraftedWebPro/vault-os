import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/vault_app_controller.dart';
import '../theme/vault_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/vault_backdrop.dart';
import '../widgets/vault_mark.dart';
import 'vault_setup_security_screen.dart';

class VaultSetupDetailsScreen extends StatefulWidget {
  const VaultSetupDetailsScreen({
    super.key,
    required this.controller,
    required this.allowReuseCurrentSecurity,
  });

  final VaultAppController controller;
  final bool allowReuseCurrentSecurity;

  static Future<void> open(
    BuildContext context, {
    required VaultAppController controller,
    required bool allowReuseCurrentSecurity,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VaultBackdrop(
          wallpaperAsset: controller.wallpaperAsset,
          child: VaultSetupDetailsScreen(
            controller: controller,
            allowReuseCurrentSecurity: allowReuseCurrentSecurity,
          ),
        ),
      ),
    );
  }

  @override
  State<VaultSetupDetailsScreen> createState() =>
      _VaultSetupDetailsScreenState();
}

class _VaultSetupDetailsScreenState extends State<VaultSetupDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vaultNameController = TextEditingController();
  final _parentDirectoryController = TextEditingController();

  @override
  void dispose() {
    _vaultNameController.dispose();
    _parentDirectoryController.dispose();
    super.dispose();
  }

  Future<void> _fillSuggestedDirectory(
    Future<String?> Function() resolver,
  ) async {
    final directory = await resolver();
    if (!mounted || directory == null || directory.isEmpty) {
      return;
    }

    setState(() {
      _parentDirectoryController.text = directory;
    });
  }

  Future<void> _browseForDirectory() async {
    final directory = await widget.controller.pickDirectory(
      initialDirectory: _parentDirectoryController.text.trim().isEmpty
          ? null
          : _parentDirectoryController.text.trim(),
      confirmButtonText: 'Choose vault parent folder',
    );
    if (!mounted || directory == null || directory.isEmpty) {
      return;
    }

    setState(() {
      _parentDirectoryController.text = directory;
    });
  }

  Future<void> _recoverExistingVaults() async {
    final directory = await widget.controller.pickDirectory(
      confirmButtonText: 'Choose folder to scan for vaults',
    );
    if (!mounted || directory == null || directory.isEmpty) {
      return;
    }
    await widget.controller.recoverVaultsFromLocation(directory);
  }

  Future<void> _importRecoveryJson() async {
    await widget.controller.importRecoveryInfo();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VaultBackdrop(
          wallpaperAsset: widget.controller.wallpaperAsset,
          child: VaultSetupSecurityScreen(
            controller: widget.controller,
            vaultName: _vaultNameController.text.trim(),
            parentDirectory: _parentDirectoryController.text.trim(),
            allowReuseCurrentSecurity: widget.allowReuseCurrentSecurity,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 80,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        if (Navigator.of(context).canPop()) ...<Widget>[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                              tooltip: 'Back',
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const VaultMark(size: 40),
                        const SizedBox(height: 14),
                        const Text('Name The Vault', style: VaultTheme.display),
                        const SizedBox(height: 6),
                        Text(
                          widget.allowReuseCurrentSecurity
                              ? 'Give the new vault a name and choose where it should live. Security comes next.'
                              : 'First give the vault a name and choose where it should live. Security comes next.',
                          textAlign: TextAlign.center,
                          style: VaultTheme.body,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Only the vault name shows in the picker. The folder location stays private there.',
                          textAlign: TextAlign.center,
                          style: VaultTheme.body.copyWith(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SectionCard(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (controller.errorMessage !=
                                    null) ...<Widget>[
                                  _InlineBanner(
                                    color: VaultTheme.danger,
                                    message: controller.errorMessage!,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                const Text(
                                  'Vault Details',
                                  style: VaultTheme.heading,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Pick a name you will recognize later.',
                                  style: VaultTheme.body,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _vaultNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Vault name',
                                    hintText:
                                        'e.g. Personal Vault, Work Files, Archive',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Give the vault a name.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _parentDirectoryController,
                                  decoration: InputDecoration(
                                    labelText: 'Parent folder path',
                                    hintText: r'F:\Vaults',
                                    suffixIcon: IconButton(
                                      onPressed: controller.isBusy
                                          ? null
                                          : _browseForDirectory,
                                      icon: const Icon(
                                        Icons.folder_open_outlined,
                                      ),
                                      tooltip: 'Browse folder',
                                    ),
                                  ),
                                  validator: (value) {
                                    final pathValue = value?.trim() ?? '';
                                    if (pathValue.isEmpty) {
                                      return 'Enter a parent folder path.';
                                    }
                                    if (!Directory(pathValue).existsSync()) {
                                      return 'That folder does not exist.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    OutlinedButton.icon(
                                      onPressed: controller.isBusy
                                          ? null
                                          : () => _fillSuggestedDirectory(
                                              controller
                                                  .suggestedDocumentsDirectory,
                                            ),
                                      icon: const Icon(
                                        Icons.folder_outlined,
                                        size: 15,
                                      ),
                                      label: const Text('Documents'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: controller.isBusy
                                          ? null
                                          : () => _fillSuggestedDirectory(
                                              controller
                                                  .suggestedDesktopDirectory,
                                            ),
                                      icon: const Icon(
                                        Icons.desktop_windows_outlined,
                                        size: 15,
                                      ),
                                      label: const Text('Desktop'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: controller.isBusy
                                          ? null
                                          : _browseForDirectory,
                                      icon: const Icon(
                                        Icons.folder_open_outlined,
                                        size: 15,
                                      ),
                                      label: const Text('Browse'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const _InfoNote(
                                  title: 'Quick notes',
                                  lines: <String>[
                                    'The app creates a hidden vault folder inside the parent folder you choose.',
                                    'You can keep multiple vaults under the same parent folder now. Each one gets its own hidden internal folder.',
                                    'You can add more vaults later from the home screen or settings.',
                                  ],
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: controller.isBusy
                                        ? null
                                        : _continue,
                                    child: const Text('Continue To Security'),
                                  ),
                                ),
                                if (!widget
                                    .allowReuseCurrentSecurity) ...<Widget>[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: controller.isBusy
                                          ? null
                                          : _recoverExistingVaults,
                                      icon: const Icon(
                                        Icons.restart_alt_outlined,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Recover Existing Vaults Instead',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: controller.isBusy
                                          ? null
                                          : _importRecoveryJson,
                                      icon: const Icon(
                                        Icons.upload_file_outlined,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Import Recovery JSON',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VaultTheme.surfaceRaised.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
        border: Border.all(color: VaultTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: VaultTheme.heading),
          const SizedBox(height: 8),
          for (final line in lines) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.tips_and_updates_outlined,
                    size: 14,
                    color: VaultTheme.brass,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(line, style: VaultTheme.body)),
              ],
            ),
            if (line != lines.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({required this.color, required this.message});

  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(message, style: TextStyle(color: color, fontSize: 12.5)),
    );
  }
}
