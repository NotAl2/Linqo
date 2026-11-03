import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../inference/model_download.dart';
import '../library/library_controller.dart';
import 'components.dart';
import 'brand.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final LibraryController controller;
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
                      !controller.processing && !lab.busy && !download.busy;
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
                              onPressed: canChange
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
                              icon: const Icon(Icons.download_rounded),
                              label: Text(
                                download.received > 0 &&
                                        download.phase != DownloadPhase.complete
                                    ? 'Resume download'
                                    : lab.model == null
                                    ? 'Download English model · 397 MB'
                                    : 'Download compact model · 397 MB',
                              ),
                            ),
                          const SizedBox(height: 8),
                          const Text(
                            'One-time download from Hugging Face. Works offline afterward. Setup needs temporary free space. Downloading a model does not load its weights.',
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
            ],
          ),
        ),
      ),
    ),
  );
}
