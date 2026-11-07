import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_checker.dart';
import 'components.dart';

class UpdatePrompt extends StatelessWidget {
  const UpdatePrompt({super.key, required this.release});
  final AvailableRelease release;
  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.system_update_rounded),
    title: Text('Linqo ${release.version} is ready'),
    content: Text(
      'A newer ${release.preview ? 'preview ' : ''}version is available. See what’s new and download the APK on GitHub.\n\nIf you choose Later, we’ll remind you in a week.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Later'),
      ),
      FilledButton(
        onPressed: () async {
          try {
            if (await launchUrl(
              release.page,
              mode: LaunchMode.externalApplication,
            )) {
              if (context.mounted) Navigator.pop(context);
            } else if (context.mounted) {
              message(
                context,
                'Could not open GitHub. Try Check for updates in Settings.',
              );
            }
          } catch (_) {
            if (context.mounted) {
              message(
                context,
                'Could not open GitHub. Try Check for updates in Settings.',
              );
            }
          }
        },
        child: const Text('View update'),
      ),
    ],
  );
}
