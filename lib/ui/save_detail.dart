import '../theme.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../library/library_controller.dart';
import '../library/models.dart';
import 'components.dart';
import 'save_editor.dart';
import 'settings_screen.dart';
import 'preview_image.dart';
import 'extracted_details.dart';
import 'extraction_progress.dart';

class SaveDetail extends StatelessWidget {
  const SaveDetail({super.key, required this.controller, required this.id});
  final LibraryController controller;
  final int id;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.changes,
    builder: (context, _, _) => FutureBuilder<SavedItem?>(
      future: controller.store.get(id),
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: snapshot.hasError
                  ? Text('Could not open this save. ${snapshot.error}')
                  : Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'Opening your save…'
                          : 'This save was removed.',
                    ),
            ),
          );
        }
        final busy = ['queued', 'running'].contains(item.status);
        final result = item.extraction;
        return Scaffold(
          appBar: AppBar(
            title: Text(item.kind.label),
            actions: [
              IconButton(
                tooltip: item.favorite ? 'Remove favourite' : 'Add favourite',
                onPressed: () async {
                  try {
                    await controller.favorite(item);
                  } catch (e) {
                    if (context.mounted) message(context, e);
                  }
                },
                icon: Icon(
                  item.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'source') {
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (context) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: .72,
                        minChildSize: .4,
                        maxChildSize: .95,
                        builder: (context, scroll) => SingleChildScrollView(
                          controller: scroll,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saved source',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              SelectableText(
                                item.body.isEmpty
                                    ? 'No source text is available yet.'
                                    : item.body,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  } else if (value == 'edit') {
                    await openPage(
                      context,
                      SaveEditor(controller: controller, item: item),
                    );
                  } else if (value == 'copy') {
                    await Clipboard.setData(
                      ClipboardData(
                        text: item.url.isNotEmpty ? item.url : item.body,
                      ),
                    );
                    if (context.mounted) message(context, 'Copied.');
                  } else if (value == 'refresh') {
                    unawaited(
                      controller.enrichPreview(item.id, item.url, item.title),
                    );
                    if (context.mounted) {
                      message(context, 'Refreshing title and image…');
                    }
                  } else if (value == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete this save?'),
                        content: const Text(
                          'This removes it from Linqo and its collections, including any private file copy. The original link or file is unaffected.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Keep it'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      try {
                        await controller.remove(item);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      }
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'source',
                    child: Text('View saved source'),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    enabled: !busy,
                    child: const Text('Edit save'),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Copy source'),
                  ),
                  if (item.url.isNotEmpty)
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh details'),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: !busy,
                    child: const Text('Delete save'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                  children: [
                    KindBadge(item.kind, size: 56),
                    const SizedBox(height: 20),
                    if (item.url.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: item.kind == SaveKind.video
                              ? VideoCover(url: item.url, child: _cover(item))
                              : _cover(item),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${item.sourceName} · ${relativeDate(item.createdAt)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Page preview',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (item.url.isNotEmpty && item.previewImage.isEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        item.imageStatus == 'pending'
                            ? 'Loading cover image…'
                            : 'No public cover image available.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => unawaited(
                            controller.enrichPreview(
                              item.id,
                              item.url,
                              item.title,
                            ),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh details'),
                        ),
                      ),
                    ],
                    if (item.collectionNames.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final name in item.collectionNames)
                            Chip(
                              label: Text(name),
                              avatar: const Icon(
                                Icons.folder_outlined,
                                size: 17,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (item.url.isNotEmpty || item.attachment.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            if (item.attachment.isNotEmpty) {
                              if (!RegExp(
                                r'^\d+(?:\.[a-zA-Z0-9]{1,8})?$',
                              ).hasMatch(item.attachment)) {
                                throw StateError(
                                  'Invalid private file reference.',
                                );
                              }
                              final root =
                                  await getApplicationSupportDirectory();
                              final file = File(
                                '${root.path}/attachments/${item.attachment}',
                              );
                              if (!await file.exists()) {
                                throw StateError(
                                  'The file copy is missing. Edit this save to attach it again.',
                                );
                              }
                              final opened = await OpenFilex.open(file.path);
                              if (opened.type != ResultType.done) {
                                throw StateError(opened.message);
                              }
                            } else if (!await launchUrl(
                              Uri.parse(item.url),
                              mode: LaunchMode.externalApplication,
                            )) {
                              throw StateError('Could not open this link.');
                            }
                          } catch (e) {
                            if (context.mounted) message(context, e);
                          }
                        },
                        icon: Icon(
                          item.attachment.isNotEmpty
                              ? Icons.open_in_new_rounded
                              : Icons.north_east_rounded,
                        ),
                        label: Text(
                          item.attachment.isNotEmpty
                              ? 'Open file'
                              : 'Open original',
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    result?.type == 'recipe'
                                        ? 'Your recipe'
                                        : result?.type == 'place'
                                        ? 'Places & details'
                                        : result?.type == 'tutorial'
                                        ? 'How to'
                                        : 'Key takeaways',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (busy && controller.activeId == item.id) ...[
                              ExtractionProgressView(lab: controller.lab),
                              const SizedBox(height: 16),
                            ],
                            if (result != null) ...[
                              ExtractedDetails(result: result),
                            ] else
                              AnimatedBuilder(
                                animation: controller.lab,
                                builder: (context, _) => Text(
                                  busy
                                      ? (item.status == 'queued'
                                            ? 'Waiting in your extraction queue. Keep browsing; your save is already here.'
                                            : controller.lab.totalParts > 1 &&
                                                  controller.activeId == item.id
                                            ? 'Processing part ${controller.lab.currentPart} of ${controller.lab.totalParts}. Keep browsing; your full source stays saved.'
                                            : 'Finding the useful bits on your device. Keep browsing while this runs.')
                                      : item.body.isEmpty
                                      ? (item.contentStatus == 'pending'
                                            ? 'Public content is being fetched automatically. Your bookmark is already saved.'
                                            : 'No usable public text was exposed. Retry content fetching or add text below.')
                                      : (item.body.length > 30000
                                            ? 'Source text is saved. Select up to 30,000 characters for extraction.'
                                            : controller.autoExtract &&
                                                  item.autoExtract &&
                                                  item.contentKind !=
                                                      'place_link' &&
                                                  controller.modelAvailable &&
                                                  item.status == 'idle' &&
                                                  supportsEnglishExtraction(
                                                    item.body,
                                                  )
                                            ? 'English details are queued automatically when source text is ready. You can also start them here.'
                                            : 'Your source text is ready for optional, private on-device summarization.'),
                                ),
                              ),
                            if (item.error.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                item.error,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (busy)
                              OutlinedButton.icon(
                                onPressed: controller.stop,
                                icon: const Icon(Icons.stop_rounded),
                                label: const Text('Stop extraction'),
                              )
                            else
                              FilledButton.icon(
                                onPressed: () async {
                                  try {
                                    if (!controller.modelAvailable) {
                                      await openPage(
                                        context,
                                        SettingsScreen(controller: controller),
                                      );
                                    } else {
                                      await controller.extract(item);
                                    }
                                  } catch (e) {
                                    if (context.mounted) message(context, e);
                                  }
                                },
                                icon: Icon(
                                  controller.modelAvailable
                                      ? Icons.auto_awesome_outlined
                                      : Icons.download_rounded,
                                ),
                                label: Text(
                                  controller.modelAvailable
                                      ? result == null
                                            ? 'Extract English details'
                                            : 'Extract again'
                                      : 'Set up optional AI',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (item.notes.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Text(
                        'Your notes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        item.notes,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                    if (item.kind == SaveKind.note) ...[
                      const SizedBox(height: 28),
                      Text(
                        'Your note',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        item.body,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                    if (item.url.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      SelectableText(
                        item.url,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _cover(SavedItem item) => SavedPreviewImage(
    name: item.previewImage,
    fallback: ColoredBox(
      color: kindColor(item.kind),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.sourceName.endsWith('instagram.com')
                  ? Icons.camera_alt_outlined
                  : kindIcon(item.kind),
              size: 42,
              color: LinqoColors.ink,
            ),
            const SizedBox(height: 8),
            Text(
              item.sourceName,
              style: const TextStyle(color: LinqoColors.ink),
            ),
          ],
        ),
      ),
    ),
  );
}
