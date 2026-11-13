import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../library/support_prompt_policy.dart';
import 'brand.dart';

class SupportPrompt extends StatefulWidget {
  const SupportPrompt({super.key, required this.policy});
  final SupportPromptPolicy policy;
  @override
  State<SupportPrompt> createState() => _SupportPromptState();
}

class _SupportPromptState extends State<SupportPrompt> {
  bool neverAgain = false, saving = false, opening = false;
  String? error;
  Future<void> remember(bool value) async {
    if (saving || opening) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.policy.setOptedOut(value);
      if (mounted) setState(() => neverAgain = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not remember that choice. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          LinqoMascot(size: 48),
          SizedBox(width: 12),
          Expanded(child: Text('Support Linqo')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A little home for your good finds, made with care. If Linqo makes your day a little easier, a coffee or tea helps us keep building. Support is always optional.',
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Don’t show again'),
            value: neverAgain,
            onChanged: saving || opening
                ? null
                : (value) => remember(value ?? false),
          ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: saving || opening ? null : () => Navigator.pop(context),
          child: const Text('Later'),
        ),
        for (final (url, label, icon) in const [
          (
            'https://buymeacoffee.com/notal2',
            'Buy me a coffee',
            Icons.coffee_outlined,
          ),
          (
            'https://buymeatea.online/notal2',
            'Buy me a tea · India',
            Icons.emoji_food_beverage_outlined,
          ),
        ])
          FilledButton.icon(
            onPressed: saving || opening
                ? null
                : () async {
                    setState(() {
                      opening = true;
                      error = null;
                    });
                    try {
                      if (!await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw StateError(
                          'Could not open the support page. Please try the support link in Settings.',
                        );
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (context.mounted) {
                        setState(
                          () => error =
                              'Could not open the support page. Try again, or use the support link in Settings.',
                        );
                      }
                    } finally {
                      if (context.mounted) setState(() => opening = false);
                    }
                  },
            icon: Icon(icon),
            label: Text(opening ? 'Opening…' : label),
          ),
      ],
    ),
  );
}
