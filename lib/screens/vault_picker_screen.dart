import 'package:flutter/material.dart';

import '../controllers/vault_app_controller.dart';
import '../models/app_config.dart';
import '../theme/vault_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/vault_mark.dart';
import 'vault_setup_details_screen.dart';

class VaultPickerScreen extends StatelessWidget {
  const VaultPickerScreen({
    super.key,
    required this.controller,
  });

  final VaultAppController controller;

  @override
  Widget build(BuildContext context) {
    final vaults = controller.vaults;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Center(child: VaultMark(size: 42)),
                  const SizedBox(height: 14),
                  const Center(child: Text('Choose A Vault', style: VaultTheme.display)),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Choose a vault to open. Only the vault you pick asks for the passphrase and biometrics.',
                      textAlign: TextAlign.center,
                      style: VaultTheme.body,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (controller.errorMessage != null) ...<Widget>[
                    _Banner(color: VaultTheme.danger, message: controller.errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (controller.statusMessage != null) ...<Widget>[
                    _Banner(color: VaultTheme.success, message: controller.statusMessage!),
                    const SizedBox(height: 12),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => VaultSetupDetailsScreen.open(
                        context,
                        controller: controller,
                        allowReuseCurrentSecurity: false,
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Create New Vault'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 920 ? 2 : 1,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.9,
                    ),
                    itemCount: vaults.length,
                    itemBuilder: (context, index) {
                      final vault = vaults[index];
                      return _VaultCard(
                        vault: vault,
                        recoveredWorkspace: controller.recoveredWorkspaceVaultIds.contains(vault.id),
                        onTap: () => controller.selectVault(vault.id),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({
    required this.vault,
    required this.recoveredWorkspace,
    required this.onTap,
  });

  final AppConfig vault;
  final bool recoveredWorkspace;
  final VoidCallback onTap;

  String get _humorLine {
    if (recoveredWorkspace) {
      return 'This vault was left open before. Open it and lock it again when you are done.';
    }
    return 'Ready to open.';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VaultTheme.radius),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const VaultMark(size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    vault.vaultName,
                    style: VaultTheme.heading.copyWith(fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _MiniPill(
                  label: recoveredWorkspace ? 'RECOVERED WORKSPACE' : 'READY TO OPEN',
                  color: recoveredWorkspace ? VaultTheme.warning : VaultTheme.success,
                ),
                if (vault.lastOpenedIso != null)
                  _MiniPill(
                    label: 'LAST OPENED ${vault.lastOpenedIso!.split('T').first}',
                    color: VaultTheme.brass,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_humorLine, style: VaultTheme.body),
            const Spacer(),
            const Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.arrow_forward_rounded, color: VaultTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.message,
  });

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
