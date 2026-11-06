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

/// Finite, native demonstrations. No network, codecs or real library writes.
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

class _TutorialSceneState extends State<TutorialScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController demo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  );
  String collection = 'Recipes';
  bool saved = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(TutorialScene old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.busy != widget.busy) sync();
  }

  void sync() {
    if (MediaQuery.disableAnimationsOf(context)) {
      demo.value = 1;
      return;
    }
    if (!widget.active || widget.busy) {
      demo.stop();
      return;
    }
    if (demo.value < 1) demo.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      sync();
    } else {
      demo.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    demo.dispose();
    super.dispose();
  }

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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: AnimatedBuilder(
              animation: demo,
              builder: (context, _) {
                final stage = saved ? 3 : (demo.value * 4).floor().clamp(0, 3);
                Widget heading(String value) => Text(
                  value,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                );
                Widget small(String value) => Text(
                  value,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.index == 0) ...[
                      Row(
                        children: [
                          for (final entry in [
                            Icons.ios_share_rounded,
                            Icons.bookmark_rounded,
                            Icons.auto_awesome_rounded,
                            Icons.check_circle_rounded,
                          ].indexed) ...[
                            if (entry.$1 > 0)
                              Expanded(
                                child: Divider(
                                  color: entry.$1 <= stage
                                      ? colors.primary
                                      : colors.outlineVariant,
                                ),
                              ),
                            AnimatedContainer(
                              duration: duration,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: entry.$1 == stage
                                    ? colors.primary
                                    : colors.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                entry.$2,
                                size: 24,
                                color: entry.$1 == stage
                                    ? colors.onPrimary
                                    : colors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 22),
                      AnimatedSwitcher(
                        duration: duration,
                        child: Column(
                          key: ValueKey(stage),
                          children: [
                            heading(
                              [
                                'Share a good find',
                                'Choose Linqo & save',
                                'Finding the useful bits',
                                'Saved to Linqo',
                              ][stage],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              [
                                'Sunday pasta · a recipe reel',
                                'The link is saved right away.',
                                'Optional on-device summary…',
                                'Sunday pasta\nServes 2 · ingredients & steps',
                              ][stage],
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      small(
                        'Demo · extraction needs the optional model and available source text.',
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() => saved = !saved);
                            if (saved) {
                              demo.stop();
                            } else if (!reduced) {
                              demo.forward(from: 0);
                            }
                          },
                          icon: Icon(
                            saved
                                ? Icons.replay_rounded
                                : Icons.bookmark_add_outlined,
                          ),
                          label: Text(saved ? 'Try again' : 'Try saving'),
                        ),
                      ),
                    ] else if (widget.index == 1) ...[
                      Icon(
                        Icons.folder_copy_outlined,
                        size: 56,
                        color: colors.onPrimaryContainer,
                      ),
                      const SizedBox(height: 16),
                      heading('Give your finds a place'),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          for (final name in ['Recipes', 'Weekend plans'])
                            ChoiceChip(
                              label: Text(name),
                              selected: collection == name,
                              onSelected: (_) =>
                                  setState(() => collection = name),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sunday pasta → $collection',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      small(
                        'Find it again with a collection or a quick search.',
                      ),
                    ] else ...[
                      heading(
                        stage < 2
                            ? 'A caption, full of good stuff'
                            : 'A recipe you can use',
                      ),
                      const SizedBox(height: 16),
                      AnimatedSize(
                        duration: duration,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: Align(
                            key: ValueKey(stage < 2),
                            alignment: Alignment.centerLeft,
                            child: stage < 2
                                ? Text(
                                    '“Sunday pasta! Serves 2. Ingredients: 200 g pasta, 2 tomatoes, 1 tbsp olive oil. Boil pasta for 10 minutes. Chop tomatoes, toss with oil, then mix with the pasta.”',
                                    style: theme.textTheme.bodyLarge,
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Sunday pasta · Serves 2',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Ingredients',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      const Text(
                                        '• 200 g pasta\n• 2 tomatoes\n• 1 tbsp olive oil',
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Steps',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      const Text(
                                        '1. Boil pasta for 10 minutes.\n2. Chop tomatoes, toss with oil, then mix with the pasta.',
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      small(
                        'Illustrative demo · no model runs during the tour.',
                      ),
                      TextButton.icon(
                        onPressed: () {
                          if (reduced) {
                            demo.value = 1;
                          } else {
                            demo.forward(from: 0);
                          }
                        },
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Replay example'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
