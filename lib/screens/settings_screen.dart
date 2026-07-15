import 'dart:ui';

import 'package:flutter/material.dart';

import '../controllers/vault_app_controller.dart';
import '../models/credits_info.dart';
import '../models/wallpaper_option.dart';
import '../theme/vault_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/vault_mark.dart';
import 'vault_setup_details_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  static const String routeName = '/settings';

  final VaultAppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<WallpaperOption>> _wallpapersFuture;

  @override
  void initState() {
    super.initState();
    _wallpapersFuture = widget.controller.loadWallpapers();
  }

  Future<void> _openSettingsModal({
    required String title,
    required String subtitle,
    required Widget child,
    bool wide = false,
  }) {
    final controller = widget.controller;
    return showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 28,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VaultTheme.radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return Container(
                    constraints: BoxConstraints(maxWidth: wide ? 980 : 560),
                    child: SectionCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(title, style: VaultTheme.heading),
                              const Spacer(),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(subtitle, style: VaultTheme.body),
                          if (controller.errorMessage != null) ...<Widget>[
                            const SizedBox(height: 14),
                            _SettingsBanner(
                              color: VaultTheme.danger,
                              message: controller.errorMessage!,
                            ),
                          ],
                          if (controller.statusMessage != null) ...<Widget>[
                            const SizedBox(height: 14),
                            _SettingsBanner(
                              color: VaultTheme.success,
                              message: controller.statusMessage!,
                            ),
                          ],
                          const SizedBox(height: 18),
                          Flexible(child: SingleChildScrollView(child: child)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showWallpaperModal() {
    const defaultSelection = '__default__';
    var selectedAsset = widget.controller.wallpaperAsset ?? defaultSelection;
    return _openSettingsModal(
      title: 'Wallpapers',
      subtitle:
          'Images from assets/themes appear here. Pick one and it becomes the background behind every glass panel.',
      wide: true,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return FutureBuilder<List<WallpaperOption>>(
            future: _wallpapersFuture,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <WallpaperOption>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...<Widget>[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        _WallpaperTile(
                          label: 'Default',
                          selected: selectedAsset == defaultSelection,
                          onTap: widget.controller.isBusy
                              ? null
                              : () => setModalState(
                                  () => selectedAsset = defaultSelection,
                                ),
                        ),
                        for (final option in items)
                          _WallpaperTile(
                            label: option.label,
                            selected: selectedAsset == option.assetPath,
                            assetPath: option.assetPath,
                            onTap: widget.controller.isBusy
                                ? null
                                : () => setModalState(
                                    () => selectedAsset = option.assetPath,
                                  ),
                          ),
                      ],
                    ),
                    if (items.isEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      const Text(
                        'No wallpaper images were discovered. If you just added files, do a full app restart once so Flutter rebuilds the asset manifest.',
                        style: VaultTheme.body,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed: widget.controller.isBusy
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: widget.controller.isBusy
                              ? null
                              : () async {
                                  await widget.controller.applyWallpaper(
                                    selectedAsset == defaultSelection
                                        ? null
                                        : selectedAsset,
                                  );
                                  if (!context.mounted) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                },
                          child: const Text('Apply Theme'),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showChangePassphraseModal() {
    final oldPassphraseController = TextEditingController();
    final newPassphraseController = TextEditingController();
    final confirmNewPassphraseController = TextEditingController();

    return _openSettingsModal(
      title: 'Change Passphrase',
      subtitle:
          'This asks for the current passphrase and re-checks biometrics before re-encrypting the vault under the new passphrase.',
      child: Column(
        children: <Widget>[
          TextField(
            controller: oldPassphraseController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current passphrase'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newPassphraseController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New passphrase'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmNewPassphraseController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new passphrase',
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.controller.isBusy
                  ? null
                  : () async {
                      if (newPassphraseController.text.trim().length < 10) {
                        return;
                      }
                      if (newPassphraseController.text !=
                          confirmNewPassphraseController.text) {
                        return;
                      }

                      await widget.controller.changePassphrase(
                        oldPassphrase: oldPassphraseController.text,
                        newPassphrase: newPassphraseController.text,
                      );
                    },
              icon: const Icon(Icons.password_outlined, size: 16),
              label: const Text('Apply new passphrase'),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      oldPassphraseController.dispose();
      newPassphraseController.dispose();
      confirmNewPassphraseController.dispose();
    });
  }

  Future<void> _showBiometricModal() {
    final passphraseController = TextEditingController();
    final gestureController = TextEditingController(text: 'Open palm');
    bool twoHandGesture = false;

    return _openSettingsModal(
      title: 'Refresh Biometrics',
      subtitle:
          'This confirms the current passphrase and current biometrics first, then opens a fresh webcam enrollment and rotates the vault to the new biometric key.',
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          children: <Widget>[
            TextField(
              controller: passphraseController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current passphrase'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: gestureController,
              decoration: const InputDecoration(labelText: 'New gesture label'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Hand Enrollment',
                style: VaultTheme.heading.copyWith(fontSize: 14),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'One hand or both hands for the gesture check.',
                style: VaultTheme.body.copyWith(fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _HandModeChip(
                  label: 'One hand',
                  selected: !twoHandGesture,
                  onTap: () => setModalState(() => twoHandGesture = false),
                ),
                _HandModeChip(
                  label: 'Both hands',
                  selected: twoHandGesture,
                  onTap: () => setModalState(() => twoHandGesture = true),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: widget.controller.isBusy
                    ? null
                    : () async {
                        if (gestureController.text.trim().isEmpty) {
                          return;
                        }

                        await widget.controller.reEnrollBiometrics(
                          currentPassphrase: passphraseController.text,
                          newGestureLabel: gestureController.text.trim(),
                          handMode: twoHandGesture ? 'double' : 'single',
                        );
                      },
                icon: const Icon(Icons.fingerprint_outlined, size: 16),
                label: const Text('Re-enroll biometrics'),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      passphraseController.dispose();
      gestureController.dispose();
    });
  }

  Future<void> _showOpenPreviousVaultModal() {
    final locationController = TextEditingController();
    final passphraseController = TextEditingController();

    return _openSettingsModal(
      title: 'Open Previous Vault',
      subtitle:
          'Point to an older vault folder or a parent folder that contains one vault, enter that vault passphrase, then confirm its biometrics. It will unlock in its own workspace so you can move files manually wherever you want.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: locationController,
            decoration: InputDecoration(
              labelText: 'Previous vault folder or parent folder',
              hintText: r'F:\OldVaultParent',
              suffixIcon: IconButton(
                onPressed: widget.controller.isBusy
                    ? null
                    : () async {
                        final pickedDirectory = await widget.controller
                            .pickDirectory(
                              initialDirectory:
                                  locationController.text.trim().isEmpty
                                  ? null
                                  : locationController.text.trim(),
                              confirmButtonText: 'Choose previous vault folder',
                            );
                        if (pickedDirectory == null ||
                            pickedDirectory.isEmpty) {
                          return;
                        }
                        locationController.text = pickedDirectory;
                      },
                icon: const Icon(Icons.folder_open_outlined),
                tooltip: 'Browse folder',
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.controller.isBusy
                ? null
                : () async {
                    final pickedDirectory = await widget.controller
                        .pickDirectory(
                          initialDirectory:
                              locationController.text.trim().isEmpty
                              ? null
                              : locationController.text.trim(),
                          confirmButtonText: 'Choose previous vault folder',
                        );
                    if (pickedDirectory == null || pickedDirectory.isEmpty) {
                      return;
                    }
                    locationController.text = pickedDirectory;
                  },
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('Browse for folder'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passphraseController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Previous vault passphrase',
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.controller.isBusy
                  ? null
                  : () async {
                      if (locationController.text.trim().isEmpty ||
                          passphraseController.text.trim().isEmpty) {
                        return;
                      }

                      await widget.controller.openPreviousVault(
                        previousParentDirectory: locationController.text.trim(),
                        previousPassphrase: passphraseController.text,
                      );
                    },
              icon: const Icon(Icons.move_down_outlined, size: 16),
              label: const Text('Unlock previous vault'),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      locationController.dispose();
      passphraseController.dispose();
    });
  }

  Future<void> _showRecoverVaultsModal() {
    final locationController = TextEditingController();

    return _openSettingsModal(
      title: 'Recover / Rescan Vaults',
      subtitle:
          'Use this if AppData was cleared, a vault was created on another machine profile, or you just want the app to rediscover vaults from disk.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: locationController,
            decoration: InputDecoration(
              labelText: 'Folder to scan',
              hintText: r'F:\VaultHub',
              suffixIcon: IconButton(
                onPressed: widget.controller.isBusy
                    ? null
                    : () async {
                        final pickedDirectory = await widget.controller
                            .pickDirectory(
                              initialDirectory:
                                  locationController.text.trim().isEmpty
                                  ? null
                                  : locationController.text.trim(),
                              confirmButtonText: 'Choose scan folder',
                            );
                        if (pickedDirectory == null ||
                            pickedDirectory.isEmpty) {
                          return;
                        }
                        locationController.text = pickedDirectory;
                      },
                icon: const Icon(Icons.folder_open_outlined),
                tooltip: 'Browse folder',
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'You can point to a vault folder itself or a parent folder that contains one or more vault folders.',
            style: VaultTheme.body,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.controller.isBusy
                  ? null
                  : () async {
                      if (locationController.text.trim().isEmpty) {
                        return;
                      }
                      await widget.controller.recoverVaultsFromLocation(
                        locationController.text.trim(),
                      );
                    },
              icon: const Icon(Icons.restart_alt_outlined, size: 16),
              label: const Text('Scan and recover vaults'),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      locationController.dispose();
    });
  }

  Future<void> _showRecoveryBackupModal() {
    return _openSettingsModal(
      title: 'Backup Recovery Info',
      subtitle:
          'Exports a JSON file the app can use later to reconnect vaults if local app data is lost.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This file does not unlock the vault by itself and it does not contain your decrypted files. It only helps Vault OS remember and reconnect vault records later.',
            style: VaultTheme.body,
          ),
          const SizedBox(height: 10),
          const Text(
            'Keep it somewhere outside AppData, like another folder, a USB drive, or your own backup location.',
            style: VaultTheme.body,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: widget.controller.isBusy
                    ? null
                    : () => widget.controller.exportRecoveryInfo(
                        selectedOnly: false,
                      ),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Export all vaults'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.isBusy
                    ? null
                    : () => widget.controller.exportRecoveryInfo(
                        selectedOnly: true,
                      ),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Export current vault'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showImportRecoveryModal() {
    return _openSettingsModal(
      title: 'Import Recovery Info',
      subtitle:
          'Use a previously exported recovery JSON file to rebuild vault records in the app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This is useful if local app data was deleted and Vault OS forgot your vault list. It restores the vault records, but you still need the real vault folder, passphrase, and biometrics to unlock anything.',
            style: VaultTheme.body,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.controller.isBusy
                  ? null
                  : () => widget.controller.importRecoveryInfo(),
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Choose recovery JSON'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetModal() {
    final resetPassphraseController = TextEditingController();
    final confirmController = TextEditingController();

    return _openSettingsModal(
      title: 'Danger Zone',
      subtitle:
          'Reset lives here only. It asks for the current passphrase, then requires biometric verification again before wiping the vault and clearing the setup.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: resetPassphraseController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current passphrase'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmController,
            decoration: const InputDecoration(
              labelText: 'Type RESET to confirm',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VaultTheme.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
              border: Border.all(
                color: VaultTheme.danger.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'This deletes the current hidden vault folder, clears the saved configuration, and takes the app back to first-time enrollment.',
              style: VaultTheme.caption,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: VaultTheme.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: widget.controller.isBusy
                  ? null
                  : () async {
                      if (confirmController.text.trim() != 'RESET') {
                        return;
                      }

                      await widget.controller.resetEnrollment(
                        currentPassphrase: resetPassphraseController.text,
                      );

                      if (!mounted || widget.controller.hasVaults) {
                        return;
                      }

                      Navigator.of(context).pop();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
              icon: const Icon(Icons.delete_forever_outlined, size: 16),
              label: const Text('Reset vault'),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      resetPassphraseController.dispose();
      confirmController.dispose();
    });
  }

  Future<void> _showCreditsModal() {
    return _openSettingsModal(
      title: 'About & Support',
      subtitle: 'A little about the app, why it exists, and how to support it if you want to.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 1. App Overview / What is it?
          const Text('About Vault OS', style: VaultTheme.heading),
          const SizedBox(height: 6),
          const Text(
            CreditsInfo.whatIsIt,
            style: VaultTheme.body,
          ),
          const SizedBox(height: 16),

          // 2. Technical Architecture Breakout
          const Text('How It Works', style: VaultTheme.heading),
          const SizedBox(height: 6),
          const Text(
            CreditsInfo.howItWorks,
            style: VaultTheme.body,
          ),
          const SizedBox(height: 16),

          // 3. Creator Profile Section
          const Divider(color: VaultTheme.border),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(Icons.badge_outlined, color: Color(0xFFB7A7F4), size: 20),
              const SizedBox(width: 8),
              Text('Built by ${CreditsInfo.creatorName}', style: VaultTheme.heading),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            CreditsInfo.aboutCreator,
            style: VaultTheme.body,
          ),
          const SizedBox(height: 16),

          // 4. Interactive Donation / Buy Me A Coffee Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFB7A7F4).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
              border: Border.all(
                color: const Color(0xFFB7A7F4).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8),
                    Text('Support The Project', style: VaultTheme.heading),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  CreditsInfo.donationPitch,
                  style: VaultTheme.body,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB7A7F4),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    try {
                      await CreditsInfo.launchDonation();
                    } catch (e) {
                      // Fallback in case launching fails or is blocked on the machine
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not launch donation link: $e')),
                      );
                    }
                  },
                  icon: const Icon(Icons.coffee_outlined, size: 16),
                  label: const Text('Support Me'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: <Widget>[
            VaultMark(size: 22),
            SizedBox(width: 10),
            Text('Settings'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (controller.errorMessage != null) ...<Widget>[
                      _SettingsBanner(
                        color: VaultTheme.danger,
                        message: controller.errorMessage!,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (controller.statusMessage != null) ...<Widget>[
                      _SettingsBanner(
                        color: VaultTheme.success,
                        message: controller.statusMessage!,
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Text('Vault Settings', style: VaultTheme.display),
                    const SizedBox(height: 6),
                    const Text(
                      'Each sensitive action opens in its own focused modal so the page stays clean and the risky stuff stays deliberate.',
                      style: VaultTheme.body,
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: MediaQuery.of(context).size.width > 780
                          ? 2
                          : 1,
                      shrinkWrap: true,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 10,
                      childAspectRatio: 5.0,
                      physics: const NeverScrollableScrollPhysics(),
                      children: <Widget>[
                        _SettingsActionCard(
                          icon: Icons.wallpaper_outlined,
                          title: 'Wallpapers',
                          subtitle:
                              'Preview and apply images from assets/themes.',
                          accent: const Color(0xFF7FD6C2),
                          onTap: _showWallpaperModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.password_outlined,
                          title: 'Change passphrase',
                          subtitle:
                              'Rotate the master phrase after biometric confirmation.',
                          accent: VaultTheme.brass,
                          onTap: _showChangePassphraseModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.add_box_outlined,
                          title: 'Create new vault',
                          subtitle:
                              'Make another vault without replacing the current one.',
                          accent: const Color(0xFF7FD6C2),
                          onTap: () => VaultSetupDetailsScreen.open(
                            context,
                            controller: widget.controller,
                            allowReuseCurrentSecurity: true,
                          ),
                        ),
                        _SettingsActionCard(
                          icon: Icons.fingerprint_outlined,
                          title: 'Refresh biometrics',
                          subtitle:
                              'Re-enroll face, blink, and gesture with a new capture.',
                          accent: const Color(0xFF9AD4FF),
                          onTap: _showBiometricModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.move_down_outlined,
                          title: 'Open previous vault',
                          subtitle:
                              'Unlock an older vault in its own workspace.',
                          accent: const Color(0xFF8AD4B0),
                          onTap: _showOpenPreviousVaultModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.restart_alt_outlined,
                          title: 'Recover / rescan vaults',
                          subtitle:
                              'Rebuild the vault list by scanning folders on disk.',
                          accent: const Color(0xFF89BFFF),
                          onTap: _showRecoverVaultsModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.backup_outlined,
                          title: 'Backup recovery info',
                          subtitle:
                              'Export vault recovery metadata to a JSON file.',
                          accent: const Color(0xFFE0C58E),
                          onTap: _showRecoveryBackupModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.upload_file_outlined,
                          title: 'Import recovery info',
                          subtitle:
                              'Restore vault records from a recovery JSON file.',
                          accent: const Color(0xFF8FD3FF),
                          onTap: _showImportRecoveryModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.delete_forever_outlined,
                          title: 'Danger zone',
                          subtitle:
                              'Reset the vault only after passphrase and biometric re-check.',
                          accent: VaultTheme.danger,
                          onTap: _showResetModal,
                        ),
                        _SettingsActionCard(
                          icon: Icons.badge_outlined,
                          title: 'Credits',
                          subtitle: 'Creator notes and authorship details.',
                          accent: const Color(0xFFB7A7F4),
                          onTap: _showCreditsModal,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Session Advice', style: VaultTheme.heading),
                          SizedBox(height: 6),
                          Text(
                            'Right now the safest habit is simple: unlock the vault when you need it, and lock it again when you are done. The vault also locks when the app closes normally. If needed later, an idle auto-lock option can be added for people who want a balance between convenience and safety.',
                            style: VaultTheme.body,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Crash Gremlin Warning',
                            style: VaultTheme.heading,
                          ),
                          SizedBox(height: 6),
                          Text(
                            CreditsInfo.crashWarning,
                            style: VaultTheme.body,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingsActionCard extends StatelessWidget {
  const _SettingsActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: VaultTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
          border: Border.all(color: VaultTheme.border),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: VaultTheme.heading.copyWith(
                      fontSize: 14,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: VaultTheme.body.copyWith(fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              color: VaultTheme.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.label,
    required this.selected,
    this.assetPath,
    this.onTap,
  });

  final String label;
  final bool selected;
  final String? assetPath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: VaultTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
          border: Border.all(
            color: selected ? VaultTheme.brass : VaultTheme.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: assetPath == null
                    ? Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Color(0xFF0A1213),
                              Color(0xFF111821),
                              Color(0xFF090A0D),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      )
                    : Image.asset(assetPath!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: VaultTheme.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsBanner extends StatelessWidget {
  const _SettingsBanner({required this.color, required this.message});

  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Text(message, style: TextStyle(color: color, fontSize: 12.5)),
    );
  }
}

class _HandModeChip extends StatelessWidget {
  const _HandModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? VaultTheme.brass.withValues(alpha: 0.12)
              : VaultTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
          border: Border.all(
            color: selected
                ? VaultTheme.brass.withValues(alpha: 0.45)
                : VaultTheme.border,
          ),
        ),
        child: Text(
          label,
          style: VaultTheme.body.copyWith(
            color: selected ? VaultTheme.brass : Colors.white70,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
