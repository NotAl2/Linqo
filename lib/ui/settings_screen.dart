import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../inference/model_download.dart';
import '../library/library_controller.dart';
import 'components.dart';
import 'brand.dart';
import 'backup_section.dart';
import 'release_settings.dart';
import 'welcome_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final LibraryController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LibraryController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(controller.recheckModel());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Make it yours')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Row(
                children: [
                  const LinqoMascot(size: 66),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'A little home for your discoveries.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final mode in ThemeMode.values)
                              ChoiceChip(
                                label: Text(switch (mode) {
                                  ThemeMode.system => 'System',
                                  ThemeMode.light => 'Light',
                                  ThemeMode.dark => 'Dark',
                                }),
                                selected: controller.theme == mode,
                                onSelected: (_) async {
                                  try {
                                    await controller.appearance(mode);
                                  } catch (e) {
                                    if (context.mounted) message(context, e);
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: Listenable.merge([
                  controller,
                  controller.lab,
                  controller.download,
                ]),
                builder: (context, _) {
                  final lab = controller.lab;
                  final download = controller.download;
                  final canChange =
                      !controller.processing && !controller.modelManagementBusy;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A little help, on-device',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Optional AI turns English captions, recipes and notes into useful details. Your library works beautifully without it. Text stays on your device.',
                          ),
                          const SizedBox(height: 20),
                          if (lab.model != null) ...[
                            Text(
                              'Model installed',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${lab.model!.name}\n${(lab.model!.bytes / 1000000).toStringAsFixed(0)} MB · ${lab.modelLoaded ? 'Loaded in memory' : 'Unloaded until needed'}',
                            ),
                            const SizedBox(height: 12),
                            if (lab.modelLoaded)
                              TextButton.icon(
                                onPressed: controller.processing || lab.busy
                                    ? null
                                    : () async {
                                        await lab.unload();
                                      },
                                icon: const Icon(Icons.memory_outlined),
                                label: const Text('Free model memory'),
                              ),
                          ],
                          if (lab.phase.name == 'restoring')
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text('Checking the remembered model…'),
                            ),
                          if (download.busy ||
                              download.phase == DownloadPhase.paused) ...[
                            if (!MediaQuery.disableAnimationsOf(context) &&
                                download.phase == DownloadPhase.downloading)
                              LinearProgressIndicator(
                                value:
                                    download.total == null ||
                                        download.total == 0
                                    ? null
                                    : (download.received / download.total!)
                                          .clamp(0, 1),
                              ),
                            const SizedBox(height: 10),
                            Text(
                              download.phase == DownloadPhase.verifying
                                  ? 'Checking and installing the download…'
                                  : '${(download.received / 1000000).toStringAsFixed(1)} MB downloaded${download.phase == DownloadPhase.paused ? ' · paused' : ''}',
                            ),
                            if (download.phase == DownloadPhase.downloading)
                              TextButton.icon(
                                onPressed: download.pause,
                                icon: const Icon(Icons.pause_rounded),
                                label: const Text('Pause download'),
                              ),
                            const SizedBox(height: 8),
                          ],
                          if (!download.busy)
                            FilledButton.icon(
                              onPressed:
                                  canChange && !controller.compactModelInstalled
                                  ? () async {
                                      try {
                                        await controller.downloadModel();
                                      } catch (e) {
                                        if (context.mounted) {
                                          message(context, e);
                                        }
                                      }
                                    }
                                  : null,
                              icon: Icon(
                                controller.compactModelInstalled
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.download_rounded,
                              ),
                              label: Text(
                                controller.compactModelInstalled
                                    ? 'Already installed'
                                    : download.received > 0 &&
                                          download.phase !=
                                              DownloadPhase.complete
                                    ? 'Resume download'
                                    : lab.model == null
                                    ? 'Download English model · 397 MB'
                                    : 'Download compact model · 397 MB',
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (lab.model != null || lab.error != null)
                            OutlinedButton.icon(
                              onPressed: canChange
                                  ? () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                            'Delete the model?',
                                          ),
                                          content: const Text(
                                            'This removes the optional model and any paused download. Your saves, collections and settings stay here. You can download the model again afterward.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Keep model'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Delete model'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true) return;
                                      try {
                                        await controller.deleteModel();
                                      } catch (e) {
                                        if (context.mounted) {
                                          message(context, e);
                                        }
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Delete model'),
                            ),
                          const SizedBox(height: 8),
                          const Text(
                            'Download from Hugging Face. Works offline afterward. Delete and redownload whenever needed. Setup needs temporary free space; downloading does not load the weights.',
                          ),
                          if (download.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              download.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          if (lab.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              lab.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: canChange
                                    ? () async {
                                        try {
                                          final picked = await FilePicker
                                              .platform
                                              .pickFiles(
                                                type: FileType.custom,
                                                allowedExtensions: ['gguf'],
                                                withData: false,
                                              );
                                          if (picked == null) return;
                                          final file = picked.files.single;
                                          if (file.path == null) {
                                            throw StateError(
                                              'Choose a GGUF from a local file provider.',
                                            );
                                          }
                                          await controller.importModel(
                                            file.path!,
                                            file.name,
                                          );
                                        } catch (e) {
                                          if (context.mounted) {
                                            message(context, e);
                                          }
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.file_open_outlined),
                                label: const Text('Import a GGUF instead'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    if (!await launchUrl(
                                      Uri.parse(
                                        'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    )) {
                                      throw StateError(
                                        'Could not open model information.',
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) message(context, e);
                                  }
                                },
                                child: const Text('Model information'),
                              ),
                            ],
                          ),
                          if (lab.phase.name == 'importing' ||
                              lab.phase.name == 'cancelling')
                            TextButton(
                              onPressed: lab.phase.name == 'cancelling'
                                  ? null
                                  : lab.cancel,
                              child: Text(
                                lab.phase.name == 'cancelling'
                                    ? 'Stopping safely…'
                                    : 'Cancel import',
                              ),
                            ),
                          const Divider(height: 28),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Summarize saves automatically'),
                            subtitle: const Text(
                              'When English source text and an installed model are available. Public content fetching works without a model.',
                            ),
                            value: controller.autoExtract,
                            onChanged: (value) async {
                              try {
                                await controller.automaticExtraction(value);
                              } catch (e) {
                                if (context.mounted) message(context, e);
                              }
                            },
                          ),
                          const Text(
                            'English extraction · 2 CPU threads\nWeights are released on backgrounding or memory pressure. Long sources may need shortening. No media transcription is included yet.',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              BackupSection(controller: controller),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.explore_outlined),
                title: const Text('A quick tour of Linqo'),
                subtitle: const Text('Sharing, collections and optional AI'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openPage(
                  context,
                  WelcomeScreen(
                    controller: controller,
                    onDone: (_) async {
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Yours, locally',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Saves, collections, notes and file copies live in Linqo’s private storage. No account needed. Uninstalling or clearing app data removes them, so keep originals of important files. Links open in their original apps or your browser.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Linqo · Android first${Platform.isAndroid ? '' : ' · shared Flutter UI'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: () => showLicensePage(
                          context: context,
                          applicationName: 'Linqo',
                        ),
                        child: const Text('Open-source licenses'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why we made Linqo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A recipe to try. A place to visit. A little spark for later. We made Linqo to give those small discoveries a home, so you can spend less time looking and more time living them.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Support Linqo',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Enjoy keeping your good finds here? You can support Linqo’s development. Donations are optional.',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            if (!await launchUrl(
                              Uri.parse('https://buymeacoffee.com/notal2'),
                              mode: LaunchMode.externalApplication,
                            )) {
                              throw StateError(
                                'Could not open Buy Me a Coffee. Visit buymeacoffee.com/notal2 in your browser.',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) message(context, e);
                          }
                        },
                        icon: const Icon(Icons.coffee_outlined),
                        label: const Text('Buy me a coffee'),
                      ),
                    ],
                  ),
                ),
              ),
              const ReleaseSettings(),
            ],
          ),
        ),
      ),
    ),
  );
}
