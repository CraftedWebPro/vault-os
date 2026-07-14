import 'package:flutter/material.dart';

import '../controllers/vault_app_controller.dart';
import 'vault_setup_details_screen.dart';

@Deprecated('Use VaultSetupDetailsScreen directly for the multi-vault flow.')
class EnrollmentScreen extends StatelessWidget {
  const EnrollmentScreen({
    super.key,
    required this.controller,
  });

  final VaultAppController controller;

  @override
  Widget build(BuildContext context) {
    return VaultSetupDetailsScreen(
      controller: controller,
      allowReuseCurrentSecurity: false,
    );
  }
}
