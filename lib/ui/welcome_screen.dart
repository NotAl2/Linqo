import 'package:flutter/material.dart';
import '../library/library_controller.dart';
import 'brand.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.controller,
    required this.onDone,
  });
  final LibraryController controller;
  final Future<void> Function(bool setupModel) onDone;
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final pages = PageController();
  int page = 0;
  bool finishing = false;
  String? error;
  static const titles = [
    'Welcome to Linqo',
    'Found it? Keep it.',
    'A little order. A lot of possibility.',
    'A little help, on your device.',
  ];
  static const descriptions = [
    'Good finds deserve a home. Keep your links, recipes, places and little ideas together.',
    'Tap Share in another app, choose Linqo, then Save. Titles and available previews arrive on their own.',
    'Make collections for your interests. Search your saved titles, notes and fetched content whenever you need them.',
    'An optional English model picks useful details from available saved text. Download it only if you want it. Your library works without it.',
  ];
  Future<void> done(bool setup) async {
    if (finishing) return;
    setState(() {
      finishing = true;
      error = null;
    });
    try {
      await widget.onDone(setup);
    } catch (_) {
      if (mounted) {
        setState(() {
          finishing = false;
          error = 'Could not finish setup. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const LinqoWordmark(),
        actions: [
          TextButton(
            onPressed: finishing ? null : () => done(false),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: pages,
                    itemCount: 4,
                    onPageChanged: (value) => setState(() => page = value),
                    itemBuilder: (context, index) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                      child: Column(
                        children: [
                          if (index == 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 30),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: reduced ? 1 : .88, end: 1),
                                duration: reduced
                                    ? Duration.zero
                                    : const Duration(milliseconds: 600),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) =>
                                    Transform.scale(scale: value, child: child),
                                child: const LinqoMascot(size: 230),
                              ),
                            )
                          else
                            TutorialScene(
                              key: ValueKey(index),
                              index: index - 1,
                              active: page == index,
                              busy: widget.controller.processing,
                            ),
                          const SizedBox(height: 28),
                          Text(
                            titles[index],
                            style: theme.textTheme.headlineLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            descriptions[index],
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          if (index == 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Some providers don’t expose captions. A thumbnail isn’t a transcript.',
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: 'Page ${page + 1} of 4',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            4,
                            (i) => AnimatedContainer(
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 160),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == page ? 22 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: i == page
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: finishing
                              ? null
                              : () {
                                  if (page == 3) {
                                    done(false);
                                  } else if (reduced) {
                                    pages.jumpToPage(page + 1);
                                  } else {
                                    pages.nextPage(
                                      duration: reduced
                                          ? Duration.zero
                                          : const Duration(milliseconds: 240),
                                      curve: Curves.easeOutCubic,
                                    );
                                  }
                                },
                          child: Text(
                            page == 0
                                ? 'Take a quick look'
                                : page == 3
                                ? 'Start my library'
                                : 'Next',
                          ),
                        ),
                      ),
                      if (page == 3)
                        TextButton(
                          onPressed: finishing ? null : () => done(true),
                          child: const Text('Set up optional AI'),
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
  }
}

/// Native examples only. No codecs, timers, network requests or real saves.
class TutorialScene extends StatefulWidget {
  const TutorialScene({
    super.key,
    required this.index,
    required this.active,
    required this.busy,
  });
  final int index;
  final bool active, busy;
  @override
  State<TutorialScene> createState() => _TutorialSceneState();
}

class _TutorialSceneState extends State<TutorialScene> {
  bool saved = false;
  String collection = 'Recipes';
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        widget.busy ||
        !widget.active;
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AnimatedContainer(
          duration: duration,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.index == 0) ...[
                AnimatedSwitcher(
                  duration: duration,
                  child: Icon(
                    saved
                        ? Icons.bookmark_added_rounded
                        : Icons.ios_share_rounded,
                    key: ValueKey(saved),
                    size: 60,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  saved ? 'Saved to Linqo' : 'Sunday pasta',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Example link · your library stays untouched',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => saved = !saved),
                  icon: Icon(
                    saved ? Icons.replay_rounded : Icons.bookmark_add_outlined,
                  ),
                  label: Text(saved ? 'Try again' : 'Try saving'),
                ),
              ] else if (widget.index == 1) ...[
                Icon(
                  Icons.folder_copy_outlined,
                  size: 56,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  'Give your finds a place',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    for (final name in ['Recipes', 'Weekend plans'])
                      ChoiceChip(
                        label: Text(name),
                        selected: collection == name,
                        onSelected: (_) => setState(() => collection = name),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: duration,
                  child: Text(
                    'Sunday pasta → $collection',
                    key: ValueKey(collection),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Search brings saved titles and notes back in a moment.',
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 56,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  'Useful details, privately',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Saved text: “Simmer for 10 minutes.”',
                  textAlign: TextAlign.center,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Icons.arrow_downward_rounded),
                ),
                const Text(
                  'Summary excerpt: “Simmer for 10 minutes.”',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Example only · no model runs during the tour.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
