import 'package:url_launcher/url_launcher.dart';

class CreditsInfo {
  const CreditsInfo._();

  static const String creatorName = 'Vivek Tamang';

  static const String whatIsIt =
      'Vault OS is a local vault app made for Windows. '
      'At first I wanted to make it for myself: something that stays on my own machine, works without the internet, '
      'and keeps files private in a way I can trust. '
      'Then I thought, if I am making this for myself anyway, why not make it open for everyone. '
      'So this app is built to run locally, store data locally, and protect files with a passphrase and biometrics '
      'without depending on any online service.';

  static const String aboutCreator =
      'Created by Vivek Tamang. '
      'I like building things that feel useful, personal, and a little different from the usual boring tools. '
      'Vault OS started from a simple need: I wanted a private local vault for my own files. '
      'No cloud, no account, no random syncing in the background. '
      'Just something secure, offline, and under my control. '
      'Then the project kept growing, and I decided to make it open so other people could use it too.';

  static const String howItWorks =
      'Each vault keeps its files and important data in encrypted form on disk. '
      'When you unlock it with your passphrase, face match, blink, and gesture, the app opens a temporary workspace '
      'so you can use your files normally. '
      'When you lock the vault again, that workspace is packed back into the encrypted vault and cleaned up.';

  static const String crashWarning =
      'If you close the app normally, it will lock the vault for you. '
      'But if the app crashes or gets killed from Task Manager, '
      'the unlocked workspace may still be left behind. '
      'If that happens, reopen the app and lock the vault properly.';

  // Donation note
  static const String donationPitch =
      'Vault OS is open and free to use. '
      'If it helps you protect your files, save your privacy, or just makes your setup feel cooler, '
      'you can support the project here. That helps me keep improving it and building more things like this.';

  static const String donationUrl = 'https://github.com/sponsors/CraftedWebPro';

  static Future<void> launchDonation() async {
    final Uri url = Uri.parse(donationUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $donationUrl');
    }
  }
}
