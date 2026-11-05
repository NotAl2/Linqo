import 'dart:async';
import 'package:flutter/material.dart';
import '../library/library_controller.dart';
import '../library/models.dart';
import 'components.dart';
import 'save_detail.dart';
import 'save_editor.dart';
import 'settings_screen.dart';
import 'brand.dart';
import '../theme.dart';

class LibraryShell extends StatefulWidget {
  const LibraryShell({super.key, required this.controller});
  final LibraryController controller;
  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int destination = 0;
  late final AnimationController navigationMotion;
  final searchKey = GlobalKey<LibraryBrowserState>();
  LibraryController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    navigationMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      value: 1,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    navigationMotion.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.foreground();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(c.background());
    }
  }

  @override
  void didHaveMemoryPressure() => unawaited(c.memoryPressure());
  void navigate(int index) {
    FocusScope.of(context).unfocus();
    if (index == destination) return;
    setState(() => destination = index);
    if (!MediaQuery.disableAnimationsOf(context)) {
      navigationMotion.forward(from: 0);
    }
    if (index == 2) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => searchKey.currentState?.focusSearch(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return PopScope(
      canPop: destination == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && destination != 0) navigate(0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const LinqoWordmark(),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: () => openPage(context, SettingsScreen(controller: c)),
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              ProcessingStrip(controller: c),
              Expanded(
                child: Row(
                  children: [
                    if (wide)
                      NavigationRail(
                        selectedIndex: destination,
                        onDestinationSelected: navigate,
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: Colors.transparent,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.bookmarks_outlined),
                            selectedIcon: Icon(Icons.bookmarks_rounded),
                            label: Text('Library'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.folder_outlined),
                            selectedIcon: Icon(Icons.folder_rounded),
                            label: Text('Collections'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.search_rounded),
                            label: Text('Search'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: FadeTransition(
                        opacity: navigationMotion.drive(
                          Tween(begin: .82, end: 1.0),
                        ),
                        child: IndexedStack(
                          index: destination,
                          children: [
                            LibraryBrowser(
                              controller: c,
                              onSearch: () => navigate(2),
                            ),
                            CollectionsView(controller: c),
                            LibraryBrowser(
                              key: searchKey,
                              controller: c,
                              search: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: ValueListenableBuilder(
          valueListenable: c.changes,
          builder: (context, _, _) => FloatingActionButton.extended(
            onPressed: () => openPage(context, SaveEditor(controller: c)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Save something'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            elevation: 0,
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: destination,
                onDestinationSelected: navigate,
                backgroundColor: Theme.of(context).colorScheme.surface,
                elevation: 0,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.bookmarks_outlined),
                    selectedIcon: Icon(Icons.bookmarks_rounded),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    selectedIcon: Icon(Icons.folder_rounded),
                    label: 'Collections',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search_rounded),
                    label: 'Search',
                  ),
                ],
              ),
      ),
    );
  }
}

class ProcessingStrip extends StatelessWidget {
  const ProcessingStrip({super.key, required this.controller});
  final LibraryController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, controller.lab]),
    builder: (context, _) {
      if (!controller.processing && controller.processingError.isEmpty) {
        return const SizedBox.shrink();
      }
      return Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
          child: Row(
            children: [
              Icon(
                controller.processing
                    ? Icons.auto_awesome_outlined
                    : Icons.info_outline_rounded,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  controller.processing
                      ? 'Extracting${controller.lab.totalParts > 1 ? ' · part ${controller.lab.currentPart}/${controller.lab.totalParts}' : ''} · ${controller.activeTitle.isEmpty ? 'Preparing model' : controller.activeTitle}'
                      : controller.processingError,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (controller.processing)
                TextButton(
                  onPressed: controller.stop,
                  child: const Text('Stop'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class LibraryBrowser extends StatefulWidget {
  const LibraryBrowser({
    super.key,
    required this.controller,
    this.search = false,
    this.collection,
    this.title,
    this.onSearch,
  });
  final LibraryController controller;
  final bool search;
  final int? collection;
  final String? title;
  final VoidCallback? onSearch;
  @override
  State<LibraryBrowser> createState() => LibraryBrowserState();
}

class LibraryBrowserState extends State<LibraryBrowser> {
  final query = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  Timer? debounce;
  SaveKind? kind;
  bool favorites = false, loading = true, more = true;
  List<SavedItem> items = [];
  String? error;
  int epoch = 0;
  LibraryController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.changes.addListener(_changed);
    scroll.addListener(_scroll);
    unawaited(fetch());
  }

  void focusSearch() => focus.requestFocus();
  void _changed() {
    if (mounted) unawaited(fetch());
  }

  void _scroll() {
    if (scroll.hasClients &&
        scroll.position.extentAfter < 400 &&
        !loading &&
        more) {
      unawaited(fetch(reset: false));
    }
  }

  Future<void> fetch({bool reset = true}) async {
    if (!reset && (loading || !more)) return;
    final request = ++epoch;
    if (reset) more = true;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final result =
          widget.search &&
              query.text.trim().isEmpty &&
              kind == null &&
              !favorites
          ? <SavedItem>[]
          : await c.store.query(
              query: query.text,
              kind: kind,
              collection: widget.collection,
              favorites: favorites,
              offset: reset ? 0 : items.length,
            );
      if (!mounted || request != epoch) return;
      setState(() {
        items = reset ? result : [...items, ...result];
        more = result.length == 40;
        loading = false;
      });
    } catch (e) {
      if (mounted && request == epoch) {
        setState(() {
          error = 'Could not read your saves. Try again.';
          loading = false;
        });
      }
    }
  }

  void filter(void Function() change) {
    setState(change);
    if (scroll.hasClients) scroll.jumpTo(0);
    unawaited(fetch());
  }

  @override
  void dispose() {
    epoch++;
    debounce?.cancel();
    c.changes.removeListener(_changed);
    query.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    final compact = !c.grid || largeText;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: RefreshIndicator(
          onRefresh: () async {
            await c.refresh();
            await fetch();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = ((constraints.maxWidth - 24) / 190).floor().clamp(
                2,
                4,
              );
              return CustomScrollView(
                controller: scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.search
                                      ? 'Find your thing.'
                                      : widget.title ?? 'Your library',
                                  style: theme.textTheme.headlineLarge,
                                ),
                              ),
                              if (!widget.search)
                                IconButton(
                                  tooltip: c.grid
                                      ? 'Switch to list'
                                      : 'Switch to grid',
                                  onPressed: () async {
                                    try {
                                      await c.layout(!c.grid);
                                    } catch (e) {
                                      if (context.mounted) message(context, e);
                                    }
                                  },
                                  icon: Icon(
                                    c.grid
                                        ? Icons.view_agenda_outlined
                                        : Icons.grid_view_rounded,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.search
                                ? 'Titles, notes, links & the useful details.'
                                : widget.collection != null
                                ? 'A few good finds, kept together.'
                                : '${c.total} ${c.total == 1 ? 'save' : 'saves'} · all on your device',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 22),
                          if (widget.search)
                            TextField(
                              key: const ValueKey('library-search'),
                              controller: query,
                              focusNode: focus,
                              maxLength: 200,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Search your saves',
                                counterText: '',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    query.clear();
                                    debounce?.cancel();
                                    unawaited(fetch());
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                              onChanged: (_) {
                                debounce?.cancel();
                                debounce = Timer(
                                  const Duration(milliseconds: 220),
                                  () => unawaited(fetch()),
                                );
                              },
                            )
                          else if (widget.onSearch != null)
                            Semantics(
                              button: true,
                              label: 'Search your saves',
                              child: Material(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(28),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(28),
                                  onTap: widget.onSearch,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.search_rounded,
                                          size: 23,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Find that thing you saved…',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All saves'),
                            selected: kind == null && !favorites,
                            onSelected: (_) => filter(() {
                              kind = null;
                              favorites = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Favourites'),
                            avatar: const Icon(
                              Icons.favorite_border_rounded,
                              size: 17,
                            ),
                            selected: favorites,
                            onSelected: (value) =>
                                filter(() => favorites = value),
                          ),
                          for (final type in SaveKind.values) ...[
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text('${type.label}s'),
                              selected: kind == type,
                              onSelected: (_) => filter(
                                () => kind = kind == type ? null : type,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (error != null)
                    SliverToBoxAdapter(
                      child: BlankSlate(
                        icon: Icons.wifi_off_rounded,
                        title: 'A small hiccup',
                        description: error!,
                        action: fetch,
                        actionLabel: 'Try again',
                      ),
                    )
                  else if (items.isEmpty && !loading)
                    SliverToBoxAdapter(
                      child: BlankSlate(
                        mascot: !widget.search && !favorites && kind == null,
                        icon: widget.search
                            ? Icons.search_rounded
                            : favorites
                            ? Icons.favorite_border_rounded
                            : Icons.bookmark_border_rounded,
                        title:
                            widget.search &&
                                query.text.trim().isEmpty &&
                                kind == null
                            ? 'It’s here somewhere.'
                            : widget.search || kind != null || favorites
                            ? 'Nothing here just yet.'
                            : 'Keep your next good find.',
                        description:
                            widget.search &&
                                query.text.trim().isEmpty &&
                                kind == null
                            ? 'Search a few words from a title, note or extracted detail. Your search stays on this device.'
                            : widget.search || kind != null || favorites
                            ? 'Try another word or filter. Your other saves are still in the library.'
                            : 'A recipe you’ll cook. A place you’ll visit. A thought worth keeping. Save it here.',
                      ),
                    )
                  else if (items.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: compact
                          ? SliverList.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) =>
                                  _card(items[index], true),
                            )
                          : SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    mainAxisExtent: 278,
                                  ),
                              itemCount: items.length,
                              itemBuilder: (context, index) =>
                                  _card(items[index], false),
                            ),
                    ),
                  if (loading)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: MediaQuery.disableAnimationsOf(context)
                              ? const Text('Reading your saves…')
                              : const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  if (more && !loading && items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton(
                          onPressed: () => fetch(reset: false),
                          child: const Text('Load more saves'),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 112)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _card(SavedItem item, bool compact) => SaveCard(
    key: ValueKey('save-${item.id}'),
    item: item,
    compact: compact,
    onTap: () => openPage(context, SaveDetail(controller: c, id: item.id)),
    onFavorite: () async {
      try {
        await c.favorite(item);
      } catch (e) {
        if (mounted) message(context, e);
      }
    },
  );
}

class CollectionsView extends StatelessWidget {
  const CollectionsView({super.key, required this.controller});
  final LibraryController controller;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.changes,
    builder: (context, _, _) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: LayoutBuilder(
          builder: (context, constraints) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good things,\ngrouped together.',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Little collections for the things you’re into.',
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => editCollection(context, controller),
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('New collection'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              if (controller.collections.isEmpty)
                SliverToBoxAdapter(
                  child: BlankSlate(
                    icon: Icons.folder_open_rounded,
                    mascot: true,
                    title: 'Make a little space.',
                    description:
                        'Recipes for the weekend. Places for someday. Give your saves a home that makes sense to you.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          MediaQuery.textScalerOf(context).scale(16) > 20
                          ? 1
                          : ((constraints.maxWidth - 24) / 210).floor().clamp(
                              2,
                              4,
                            ),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent:
                          MediaQuery.textScalerOf(context).scale(16) > 20
                          ? 360
                          : 218,
                    ),
                    itemCount: controller.collections.length,
                    itemBuilder: (context, index) {
                      final collection = controller.collections[index];
                      return Card(
                        color: accents[collection.color % accents.length],
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => openPage(
                            context,
                            CollectionPage(
                              controller: controller,
                              collection: collection,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 8, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.folder_open_rounded,
                                      color: LinqoColors.ink,
                                      size: 28,
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Edit ${collection.name}',
                                      onPressed: () => editCollection(
                                        context,
                                        controller,
                                        collection: collection,
                                      ),
                                      icon: const Icon(
                                        Icons.more_horiz_rounded,
                                        color: LinqoColors.ink,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    collection.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(color: LinqoColors.ink),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${collection.count} ${collection.count == 1 ? 'save' : 'saves'}',
                                  style: const TextStyle(
                                    color: Color(0xFF65447E),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    collection.preview.isEmpty
                                        ? 'Room for a good find.'
                                        : collection.preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF65447E),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 112)),
            ],
          ),
        ),
      ),
    ),
  );
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({
    super.key,
    required this.controller,
    required this.collection,
  });
  final LibraryController controller;
  final SaveCollection collection;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.changes,
    builder: (context, _, _) {
      final current = controller.collections
          .where((c) => c.id == collection.id)
          .firstOrNull;
      if (current == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Collection')),
          body: const BlankSlate(
            icon: Icons.folder_open_rounded,
            title: 'Collection removed',
            description: 'Your saves are still in the library.',
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Collection'),
          actions: [
            IconButton(
              tooltip: 'Edit collection',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  editCollection(context, controller, collection: current),
            ),
          ],
        ),
        body: SafeArea(
          child: LibraryBrowser(
            controller: controller,
            collection: collection.id,
            title: current.name,
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => openPage(
            context,
            SaveEditor(
              controller: controller,
              initialCollection: collection.id,
            ),
          ),
          tooltip: 'Save to collection',
          child: const Icon(Icons.add_rounded),
        ),
      );
    },
  );
}

Future<void> editCollection(
  BuildContext context,
  LibraryController controller, {
  SaveCollection? collection,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      CollectionEditor(controller: controller, collection: collection),
);

class CollectionEditor extends StatefulWidget {
  const CollectionEditor({
    super.key,
    required this.controller,
    this.collection,
  });
  final LibraryController controller;
  final SaveCollection? collection;
  @override
  State<CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends State<CollectionEditor> {
  late final name = TextEditingController(text: widget.collection?.name ?? '');
  late int color = widget.collection?.color ?? 0;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.collection(
        name.text,
        color,
        id: widget.collection?.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString().contains('UNIQUE')
              ? 'You already have a collection with that name.'
              : e.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.collection == null
                ? 'A new little collection'
                : 'Edit collection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: name,
            enabled: !busy,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Collection name',
              hintText: 'Weekend recipes',
              errorText: error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => busy ? null : save(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < accents.length; i++)
                Semantics(
                  selected: color == i,
                  button: true,
                  label: 'Collection colour ${i + 1}',
                  child: InkWell(
                    onTap: busy ? null : () => setState(() => color = i),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accents[i],
                        shape: BoxShape.circle,
                      ),
                      child: color == i
                          ? const Icon(
                              Icons.check_rounded,
                              color: LinqoColors.ink,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save collection'),
          ),
          if (widget.collection != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete this collection?'),
                          content: const Text(
                            'Your saves stay in the library. Only the collection is removed.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Keep it'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete collection'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        try {
                          await widget.controller.removeCollection(
                            widget.collection!.id,
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        }
                      }
                    },
              child: const Text('Delete collection'),
            ),
        ],
      ),
    ),
  );
}
