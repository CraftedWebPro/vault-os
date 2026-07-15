import 'package:flutter/material.dart';

import '../controllers/vault_app_controller.dart';
import '../theme/vault_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/vault_mark.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.controller,
  });

  final VaultAppController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passphraseController = TextEditingController();

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final config = controller.config;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SectionCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: controller.isBusy ? null : controller.backToVaultPicker,
                        icon: const Icon(Icons.arrow_back_rounded),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 10),
                      const VaultMark(size: 30),
                      const SizedBox(width: 10),
                      const Text('Unlock Vault', style: VaultTheme.heading),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    config == null ? 'No vault selected.' : config.vaultName,
                    style: VaultTheme.display.copyWith(fontSize: 22),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    controller.recoveredWorkspaceVaultIds.contains(config?.id)
                        ? 'This vault was left open after an earlier exit. Unlock it, then lock it again properly.'
                        : 'Enter your passphrase first, then complete the biometric check.',
                    style: VaultTheme.body,
                  ),
                  const SizedBox(height: 14),
                  const Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      StatusPill(label: 'FACE', tone: PillTone.brass, icon: Icons.face_retouching_natural),
                      StatusPill(label: 'BLINK', tone: PillTone.brass, icon: Icons.visibility_outlined),
                      StatusPill(label: 'GESTURE', tone: PillTone.brass, icon: Icons.back_hand_outlined),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (controller.errorMessage != null) ...<Widget>[
                    _InlineMessage(tone: PillTone.danger, message: controller.errorMessage!),
                    const SizedBox(height: 4),
                    const Text(
                      'Yes, this is on purpose. The vault is picky — it\'s a feature, not a bug.',
                      style: VaultTheme.caption,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (controller.statusMessage != null) ...<Widget>[
                    _InlineMessage(tone: PillTone.success, message: controller.statusMessage!),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _passphraseController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Vault passphrase'),
                    onSubmitted: controller.isBusy
                        ? null
                        : (_) => controller.unlock(_passphraseController.text),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'The check goes in this order: face, blink, then gesture.',
                    style: VaultTheme.caption,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: controller.isBusy ? null : () => controller.unlock(_passphraseController.text),
                      child: Text(controller.isBusy ? 'Verifying...' : 'Open This Vault'),
                    ),
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

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.tone,
    required this.message,
  });

  final PillTone tone;
  final String message;

  Color get _color => tone == PillTone.danger ? VaultTheme.danger : VaultTheme.success;

  @override
  Widget build(BuildContext context) {
    final color = _color;
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
