import 'package:flutter/material.dart';

import '../controllers/vault_app_controller.dart';
import '../theme/vault_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/vault_mark.dart';

class VaultSetupSecurityScreen extends StatefulWidget {
  const VaultSetupSecurityScreen({
    super.key,
    required this.controller,
    required this.vaultName,
    required this.parentDirectory,
    required this.allowReuseCurrentSecurity,
  });

  final VaultAppController controller;
  final String vaultName;
  final String parentDirectory;
  final bool allowReuseCurrentSecurity;

  @override
  State<VaultSetupSecurityScreen> createState() =>
      _VaultSetupSecurityScreenState();
}

class _VaultSetupSecurityScreenState extends State<VaultSetupSecurityScreen> {
  bool _reuseCurrentSecurity = false;
  bool _showNewPassphrase = false;
  final _newPassphraseController = TextEditingController();
  final _confirmNewPassphraseController = TextEditingController();
  final _gestureController = TextEditingController(text: 'Open palm');
  final _currentPassphraseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reuseCurrentSecurity = widget.allowReuseCurrentSecurity;
  }

  @override
  void dispose() {
    _newPassphraseController.dispose();
    _confirmNewPassphraseController.dispose();
    _gestureController.dispose();
    _currentPassphraseController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reuseCurrentSecurity) {
      if (_currentPassphraseController.text.trim().isEmpty) {
        return;
      }
      await widget.controller.createVaultWithReusedSecurity(
        vaultName: widget.vaultName,
        parentDirectory: widget.parentDirectory,
        currentPassphrase: _currentPassphraseController.text,
      );
    } else {
      if (_newPassphraseController.text.trim().length < 10) {
        return;
      }
      if (_newPassphraseController.text !=
          _confirmNewPassphraseController.text) {
        return;
      }
      if (_gestureController.text.trim().isEmpty) {
        return;
      }
      await widget.controller.createVaultWithNewSecurity(
        vaultName: widget.vaultName,
        parentDirectory: widget.parentDirectory,
        passphrase: _newPassphraseController.text,
        gestureLabel: _gestureController.text.trim(),
      );
    }

    if (!mounted || !widget.controller.isUnlocked) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
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
                    constraints: const BoxConstraints(maxWidth: 680),
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
                        Text(
                          widget.vaultName,
                          style: VaultTheme.display,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Now set the security for this vault.',
                          textAlign: TextAlign.center,
                          style: VaultTheme.body,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You can reuse the current vault security or create a new one for this vault.',
                          textAlign: TextAlign.center,
                          style: VaultTheme.body.copyWith(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (controller.errorMessage != null) ...<Widget>[
                                _InlineBanner(
                                  color: VaultTheme.danger,
                                  message: controller.errorMessage!,
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (widget.allowReuseCurrentSecurity) ...<Widget>[
                                const Text(
                                  'Security Mode',
                                  style: VaultTheme.heading,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Choose whether this vault should reuse the current security or have its own.',
                                  style: VaultTheme.body,
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: <Widget>[
                                    _ModeCard(
                                      title: 'Reuse current',
                                      subtitle:
                                          'Same passphrase and biometrics. Quick and smooth.',
                                      selected: _reuseCurrentSecurity,
                                      onTap: () => setState(
                                        () => _reuseCurrentSecurity = true,
                                      ),
                                    ),
                                    _ModeCard(
                                      title: 'Create new',
                                      subtitle:
                                          'New passphrase, new gesture, new full enrollment.',
                                      selected: !_reuseCurrentSecurity,
                                      onTap: () => setState(
                                        () => _reuseCurrentSecurity = false,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                              ],
                              if (_reuseCurrentSecurity) ...<Widget>[
                                const Text(
                                  'Reuse Current Security',
                                  style: VaultTheme.heading,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'We will ask for the current passphrase and run the current biometric check once, then stamp the new vault with that same setup.',
                                  style: VaultTheme.body,
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _currentPassphraseController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Current vault passphrase',
                                  ),
                                ),
                              ] else ...<Widget>[
                                const Text(
                                  'Create New Security',
                                  style: VaultTheme.heading,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'This will open the webcam flow for face, blink, and gesture enrollment after the passphrase fields are set.',
                                  style: VaultTheme.body,
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _newPassphraseController,
                                  obscureText: !_showNewPassphrase,
                                  decoration: InputDecoration(
                                    labelText: 'Master passphrase',
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _showNewPassphrase =
                                            !_showNewPassphrase,
                                      ),
                                      icon: Icon(
                                        _showNewPassphrase
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _confirmNewPassphraseController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm passphrase',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _gestureController,
                                  decoration: const InputDecoration(
                                    labelText: 'Gesture name',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _InfoNote(
                                title: _reuseCurrentSecurity
                                    ? 'Before you continue'
                                    : 'Enrollment notes',
                                lines: _reuseCurrentSecurity
                                    ? const <String>[
                                        'You only need to prove the current vault is really yours once.',
                                        'After that, the new vault inherits the same passphrase and biometrics.',
                                      ]
                                    : const <String>[
                                        'Pick a passphrase you can remember.',
                                        'The next step opens the webcam for face, blink, and gesture setup.',
                                      ],
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: controller.isBusy ? null : _submit,
                                  child: Text(
                                    controller.isBusy
                                        ? 'Preparing vault...'
                                        : _reuseCurrentSecurity
                                        ? 'Create Vault With Current Security'
                                        : 'Create Vault And Start Enrollment',
                                  ),
                                ),
                              ),
                            ],
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
                    Icons.shield_moon_outlined,
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VaultTheme.radiusSmall),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(14),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: VaultTheme.heading),
            const SizedBox(height: 6),
            Text(subtitle, style: VaultTheme.body),
          ],
        ),
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
