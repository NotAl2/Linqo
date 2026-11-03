import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../library/models.dart';
import 'preview_image.dart';
import 'brand.dart';
import '../theme.dart';

Future<void> openOriginalLink(BuildContext context, String url) async {
  try {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Could not open this link.');
    }
  } catch (error) {
    if (context.mounted) message(context, error);
  }
}

class VideoCover extends StatelessWidget {
  const VideoCover({super.key, required this.url, required this.child});
  final String url;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: IconButton.filled(
            tooltip: 'Open video in original app',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: LinqoColors.ink,
            ),
            onPressed: () => openOriginalLink(context, url),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ),
      ),
    ],
  );
}

const accents = [
  LinqoColors.yellow,
  LinqoColors.lavender,
  LinqoColors.mint,
  LinqoColors.lilac,
  LinqoColors.pink,
  Color(0xFFE8DAFF),
];
IconData kindIcon(SaveKind kind) => switch (kind) {
  SaveKind.link => Icons.link_rounded,
  SaveKind.video => Icons.play_arrow_rounded,
  SaveKind.recipe => Icons.restaurant_rounded,
  SaveKind.place => Icons.place_outlined,
  SaveKind.note => Icons.edit_note_rounded,
  SaveKind.file => Icons.description_outlined,
};
Color kindColor(SaveKind kind) =>
    accents[switch (kind) {
      SaveKind.link => 3,
      SaveKind.video => 1,
      SaveKind.recipe => 0,
      SaveKind.place => 2,
      SaveKind.note => 5,
      SaveKind.file => 4,
    }];
Duration motionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);
Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => page,
        transitionDuration: motionDuration(context),
        reverseTransitionDuration: motionDuration(context),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.025), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        ),
      ),
    );
void message(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error.toString().replaceFirst(
          RegExp(r'^(?:Bad state: |FormatException: )'),
          '',
        ),
      ),
    ),
  );
}

String relativeDate(DateTime time) {
  final days = DateTime.now().difference(time).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[time.month - 1]} ${time.day}';
}

class KindBadge extends StatelessWidget {
  const KindBadge(this.kind, {super.key, this.size = 40});
  final SaveKind kind;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: kindColor(kind), shape: BoxShape.circle),
    child: Icon(kindIcon(kind), size: size * .53, color: LinqoColors.ink),
  );
}

class BlankSlate extends StatelessWidget {
  const BlankSlate({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.actionLabel,
    this.mascot = false,
  });
  final IconData icon;
  final String title, description;
  final VoidCallback? action;
  final String? actionLabel;
  final bool mascot;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mascot)
          const LinqoMascot(size: 136)
        else
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(
              icon,
              size: 38,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: action,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

class SaveCard extends StatelessWidget {
  const SaveCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onFavorite,
    this.compact = false,
  });
  final SavedItem item;
  final VoidCallback onTap, onFavorite;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final processing = ['queued', 'running'].contains(item.status);
    final subtitle = item.summary.isNotEmpty
        ? item.summary
        : item.body.isNotEmpty
        ? item.body
        : item.notes.isNotEmpty
        ? item.notes
        : item.description;
    final cover = SavedPreviewImage(
      name: item.previewImage,
      fallback: Container(
        color: kindColor(item.kind),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.sourceName == 'instagram.com'
                      ? Icons.camera_alt_outlined
                      : kindIcon(item.kind),
                  size: 21,
                  color: LinqoColors.ink,
                ),
                const Spacer(),
                if (processing)
                  const Icon(
                    Icons.hourglass_top_rounded,
                    size: 18,
                    color: LinqoColors.ink,
                  )
                else
                  Text(
                    item.kind.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .7,
                      color: LinqoColors.ink,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              subtitle.trim().isEmpty ? item.sourceName : subtitle.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: item.kind == SaveKind.note ? 18 : 14,
                height: 1.35,
                fontWeight: item.kind == SaveKind.note
                    ? FontWeight.w500
                    : FontWeight.w400,
                color: LinqoColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
    return RepaintBoundary(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: compact
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child:
                              item.kind == SaveKind.video && item.url.isNotEmpty
                              ? VideoCover(
                                  url: item.url,
                                  child: SavedPreviewImage(
                                    name: item.previewImage,
                                    fallback: KindBadge(item.kind, size: 56),
                                  ),
                                )
                              : SavedPreviewImage(
                                  name: item.previewImage,
                                  fallback: KindBadge(item.kind, size: 56),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              processing
                                  ? 'Extracting details…'
                                  : item.sourceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (item.collectionNames.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                item.collectionNames.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onFavorite,
                        tooltip: item.favorite
                            ? 'Remove favourite'
                            : 'Add favourite',
                        icon: Icon(
                          item.favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 20,
                          color: item.favorite
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: item.kind == SaveKind.video && item.url.isNotEmpty
                          ? VideoCover(url: item.url, child: cover)
                          : cover,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          height: 1.25,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                      child: Text(
                        item.collectionNames.isNotEmpty
                            ? item.collectionNames.first
                            : item.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 14, right: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              processing
                                  ? (item.status == 'queued'
                                        ? 'Queued'
                                        : 'Extracting…')
                                  : relativeDate(item.createdAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: onFavorite,
                            tooltip: item.favorite
                                ? 'Remove favourite'
                                : 'Add favourite',
                            icon: Icon(
                              item.favorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 19,
                              color: item.favorite
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
