import '../theme.dart';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../library/library_controller.dart';
import '../library/models.dart';
import 'components.dart';
import '../sharing/shared_content.dart';
import '../sharing/link_preview.dart';
import 'preview_image.dart';

class SaveEditor extends StatefulWidget {
  const SaveEditor({
    super.key,
    required this.controller,
    this.item,
    this.initialCollection,
    this.shared,
    this.previewFactory,
  });
  final LibraryController controller;
  final SavedItem? item;
  final int? initialCollection;
  final SharedContent? shared;
  final PreviewJob Function(String)? previewFactory;
  @override
  State<SaveEditor> createState() => _SaveEditorState();
}

class _SaveEditorState extends State<SaveEditor> {
  final _form = GlobalKey<FormState>();
  late final title = TextEditingController(
    text: widget.item?.title ?? widget.shared?.title ?? '',
  );
  late final link = TextEditingController(
    text: widget.item?.url ?? widget.shared?.url ?? '',
  );
  late final body = TextEditingController(
    text: widget.item?.body ?? widget.shared?.notes ?? '',
  );
  late final notes = TextEditingController(text: widget.item?.notes ?? '');
  late SaveKind kind =
      widget.item?.kind ?? widget.shared?.kind ?? SaveKind.link;
  late final Set<int> selected = {
    ...?widget.item?.collectionIds,
    if (widget.initialCollection != null) widget.initialCollection!,
  };
  String? pickedPath;
  late String fileName = widget.item?.fileName ?? '';
  bool saving = false, extract = false, picking = false;
  late bool _kindTouched = widget.item != null;
  bool _titleTouched = false, _previewLoading = false, _handedOff = false;
  String _lookupUrl = '';
  PreviewJob? _request;
  LinkPreview? _preview;
  Timer? _lookupTimer;
  bool get _autoTitle =>
      !_titleTouched && (widget.item == null || widget.item!.autoTitle);

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null && item.url.isNotEmpty) {
      _lookupUrl = item.url;
      _preview = LinkPreview(
        title: item.title,
        description: item.description,
        image: item.previewImage,
        resolvedUrl: item.resolvedUrl,
        available: item.previewStatus == 'ready',
        imageStatus: item.imageStatus,
      );
    } else if (link.text.isNotEmpty) {
      if (PreviewCache.validName(widget.shared?.image ?? '')) {
        _lookupUrl = link.text;
        _preview = LinkPreview(
          image: widget.shared!.image,
          imageStatus: 'ready',
          available: true,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_lookup());
      });
    }
  }

  void _linkChanged(String _) {
    _lookupTimer?.cancel();
    // Invalidate old metadata immediately, including while the debounce runs.
    _request?.cancel();
    _request = null;
    setState(() {
      _preview = null;
      _lookupUrl = '';
      _previewLoading = false;
      try {
        final url = normalizeWebUrl(link.text);
        if (url.isNotEmpty) {
          if (_autoTitle) title.text = fallbackLinkTitle(Uri.parse(url));
          if (!_kindTouched) kind = inferKind(url);
        }
      } on FormatException {
        // Validation stays with the link field.
      }
    });
    _lookupTimer = Timer(
      const Duration(milliseconds: 550),
      () => unawaited(_lookup()),
    );
  }

  Future<void> _lookup() async {
    String url;
    try {
      url = normalizeWebUrl(link.text);
    } on FormatException {
      return;
    }
    if (!mounted || saving || url.isEmpty) return;
    _request?.cancel();
    final previous = _lookupUrl == url ? _preview : null;
    final job = widget.previewFactory?.call(url) ?? PreviewRequest(url);
    _request = job;
    setState(() {
      _lookupUrl = url;
      _preview = previous;
      _previewLoading = true;
      if (!_kindTouched) kind = inferKind(url);
      if (_autoTitle && title.text.trim().isEmpty) {
        title.text = url == widget.shared?.url
            ? widget.shared!.title
            : fallbackLinkTitle(Uri.parse(url));
      }
    });
    unawaited(
      job.metadata.then((metadata) {
        if (!mounted || !identical(_request, job)) return;
        setState(() {
          _preview = mergePreview(previous, metadata);
          if (!saving && _autoTitle && metadata.title.isNotEmpty) {
            title.text = metadata.title;
          }
        });
      }),
    );
    final preview = await job.future;
    if (!mounted || !identical(_request, job)) return;
    setState(() {
      _preview = mergePreview(previous, preview);
      _previewLoading = false;
      if (!saving && _autoTitle && preview.title.isNotEmpty) {
        title.text = preview.title;
      }
      if (!_kindTouched && inferKind(preview.resolvedUrl) == SaveKind.place) {
        kind = SaveKind.place;
      }
    });
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    if (!_handedOff) _request?.cancel();
    title.dispose();
    link.dispose();
    body.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.path == null) {
        throw StateError(
          'This provider cannot supply the file. Try another file.',
        );
      }
      if (file.size > 100 * 1024 * 1024) {
        throw StateError(
          'Choose a file under 100 MB. Save a link for larger media.',
        );
      }
      setState(() {
        pickedPath = file.path;
        fileName = file.name;
        kind = SaveKind.file;
        if (title.text.trim().isEmpty) title.text = file.name;
      });
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _save() async {
    if (saving || picking) return;
    if (!_form.currentState!.validate()) return;
    if (kind == SaveKind.file && fileName.isEmpty) {
      message(context, 'Choose a file to attach first.');
      return;
    }
    setState(() => saving = true);
    String attachment = widget.item?.attachment ?? '';
    File? copied;
    var committed = false;
    try {
      final savedUrl = normalizeWebUrl(link.text);
      final preview = _lookupUrl == savedUrl ? _preview : null;
      final job = _lookupUrl == savedUrl ? _request : null;
      final savedTitle = title.text;
      if (pickedPath != null) {
        final root = Directory(
          '${(await getApplicationSupportDirectory()).path}/attachments',
        );
        await root.create(recursive: true);
        // A unique app-owned name prevents provider paths from escaping storage.
        final extension =
            RegExp(r'\.[a-zA-Z0-9]{1,8}$').firstMatch(fileName)?.group(0) ?? '';
        attachment = '${DateTime.now().microsecondsSinceEpoch}$extension';
        final target = '${root.path}/$attachment';
        final source = pickedPath!;
        copied = File(target);
        await Isolate.run(() async {
          if (await File(source).length() > 100 * 1024 * 1024) {
            throw const FormatException('Choose a file under 100 MB.');
          }
          await File(source).copy(target);
        });
      }
      final id = await widget.controller.save(
        SaveDraft(
          title: title.text,
          body: body.text,
          notes: notes.text,
          url: link.text,
          kind: kind,
          collectionIds: selected.toList(),
          fileName: fileName,
          attachment: attachment,
          description: preview?.description ?? '',
          previewImage: preview?.image ?? '',
          imageStatus:
              preview?.imageStatus ?? (savedUrl.isEmpty ? 'none' : 'pending'),
          previewStatus: savedUrl.isEmpty
              ? 'none'
              : preview == null
              ? 'pending'
              : preview.available
              ? 'ready'
              : 'unavailable',
          resolvedUrl: preview?.resolvedUrl ?? '',
          autoTitle: _autoTitle,
          shareId: widget.shared?.id ?? '',
        ),
        id: widget.item?.id,
      );
      committed = true;
      if (savedUrl.isNotEmpty) {
        _handedOff = job != null;
        unawaited(
          widget.controller.enrichPreview(
            id,
            savedUrl,
            savedTitle,
            request: job,
            ready: _previewLoading ? null : preview,
          ),
        );
      }
      final previous = widget.item?.attachment ?? '';
      if (copied != null &&
          previous.isNotEmpty &&
          previous != attachment &&
          RegExp(r'^\d+(?:\.[a-zA-Z0-9]{1,8})?$').hasMatch(previous)) {
        try {
          final root = await getApplicationSupportDirectory();
          final old = File('${root.path}/attachments/$previous');
          if (await old.exists()) await old.delete();
        } on FileSystemException {
          /* The committed save remains valid. */
        }
      }
      if (extract) {
        final item = await widget.controller.store.get(id);
        if (item != null) {
          try {
            await widget.controller.extract(item);
          } catch (e) {
            if (mounted) message(context, e);
          }
        }
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (!committed && copied != null && await copied.exists()) {
        await copied.delete();
      }
      if (mounted) {
        message(context, e);
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.item == null ? 'Save something good' : 'Edit save',
          ),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 632),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saving || picking ? null : _save,
                      icon: Icon(
                        saving
                            ? Icons.hourglass_top_rounded
                            : Icons.bookmark_add_outlined,
                      ),
                      label: Text(saving ? 'Saving…' : 'Save to Linqo'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  children: [
                    Text(
                      widget.shared == null
                          ? 'A link, a thought, a little discovery.'
                          : 'Shared to Linqo. Save now; the preview can catch up.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in SaveKind.values)
                          ChoiceChip(
                            showCheckmark: false,
                            label: Text(type.label),
                            avatar: Icon(kindIcon(type), size: 18),
                            selected: kind == type,
                            onSelected: saving
                                ? null
                                : (_) => setState(() {
                                    kind = type;
                                    _kindTouched = true;
                                  }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: title,
                      onChanged: (_) => _titleTouched = true,
                      enabled: !saving,
                      maxLength: 180,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'What do you want to remember?',
                        counterText: '',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Give your save a title.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (kind != SaveKind.note && kind != SaveKind.file ||
                        link.text.isNotEmpty) ...[
                      TextFormField(
                        controller: link,
                        onChanged: _linkChanged,
                        enabled: !saving,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Link',
                          hintText: 'https://…',
                          suffixIcon: IconButton(
                            tooltip: 'Paste link',
                            icon: const Icon(Icons.content_paste_rounded),
                            onPressed: saving
                                ? null
                                : () async {
                                    final value = await Clipboard.getData(
                                      'text/plain',
                                    );
                                    if (!mounted) return;
                                    link.text = value?.text ?? '';
                                    _linkChanged(link.text);
                                    _lookupTimer?.cancel();
                                    unawaited(_lookup());
                                  },
                          ),
                        ),
                        validator: (value) {
                          try {
                            normalizeWebUrl(value ?? '');
                            return null;
                          } catch (_) {
                            return 'Enter a valid http or https link.';
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_lookupUrl.isNotEmpty) ...[
                      _previewPanel(),
                      const SizedBox(height: 20),
                    ],
                    if (kind == SaveKind.file) ...[
                      OutlinedButton.icon(
                        onPressed: saving || picking ? null : _pick,
                        icon: const Icon(Icons.attach_file_rounded),
                        label: Text(
                          picking
                              ? 'Choosing file…'
                              : fileName.isEmpty
                              ? 'Choose a file'
                              : fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A private copy stays available offline. Up to 100 MB per file.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (kind == SaveKind.note)
                      _sourceField()
                    else ...[
                      TextFormField(
                        key: const ValueKey('save-notes'),
                        controller: notes,
                        enabled: !saving,
                        minLines: 2,
                        maxLines: 6,
                        maxLength: 30000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Your notes — optional',
                          hintText: 'Why do you want to keep this?',
                          alignLabelWithHint: true,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8),
                      ExpansionTile(
                        key: const ValueKey('extraction-content'),
                        tilePadding: EdgeInsets.zero,
                        initiallyExpanded: body.text.isNotEmpty,
                        title: const Text('Content for extraction'),
                        subtitle: Text(
                          body.text.isEmpty
                              ? 'No caption or transcript available'
                              : 'Shared or pasted text · English AI is optional',
                        ),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text(
                              'A preview image does not include the video’s contents. Add an English caption, recipe or transcript to summarize it.',
                            ),
                          ),
                          _sourceField(),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Collections',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (c.collections.isEmpty)
                      const Text(
                        'You can organise this save into a collection later.',
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final collection in c.collections)
                            FilterChip(
                              label: Text(collection.name),
                              selected: selected.contains(collection.id),
                              onSelected: saving
                                  ? null
                                  : (value) => setState(() {
                                      value
                                          ? selected.add(collection.id)
                                          : selected.remove(collection.id);
                                    }),
                            ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    if (c.modelAvailable)
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Extract English details'),
                        subtitle: const Text(
                          'Optional. You can keep browsing while it runs.',
                        ),
                        value: extract,
                        onChanged: saving || body.text.trim().isEmpty
                            ? null
                            : (value) => setState(() => extract = value),
                      )
                    else
                      const Text(
                        'AI is optional. You can add it later in Settings.',
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewPanel() {
    final preview = _preview;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 80,
              height: 80,
              child: SavedPreviewImage(
                name: preview?.image ?? '',
                fallback: ColoredBox(
                  color: kindColor(kind),
                  child: Icon(
                    Uri.tryParse(_lookupUrl)?.host.endsWith('instagram.com') ==
                            true
                        ? Icons.camera_alt_outlined
                        : kindIcon(kind),
                    color: LinqoColors.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _previewLoading
                    ? preview?.available == true
                          ? 'Loading image…'
                          : 'Looking up preview…'
                    : preview?.available == true
                    ? 'Link preview'
                    : 'Your link is ready to save',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _previewLoading
                    ? 'You can save without waiting.'
                    : preview?.description.isNotEmpty == true
                    ? preview!.description
                    : preview?.available == true
                    ? 'From ${Uri.tryParse(_lookupUrl)?.host ?? 'the original website'}'
                    : 'No public image or details available. Your original link is kept.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!_previewLoading)
                TextButton(
                  onPressed: saving ? null : () => unawaited(_lookup()),
                  child: const Text('Refresh details'),
                ),
              TextButton.icon(
                onPressed: () => openOriginalLink(context, _lookupUrl),
                icon: const Icon(Icons.north_east_rounded, size: 18),
                label: const Text('Open original'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceField() => TextFormField(
    key: const ValueKey('save-source'),
    controller: body,
    enabled: !saving,
    minLines: 4,
    maxLines: 12,
    maxLength: 30000,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(
      labelText: kind == SaveKind.note
          ? 'Your note'
          : 'Caption, recipe or transcript',
      hintText: kind == SaveKind.note
          ? 'Write something worth keeping…'
          : 'Paste English content here…',
      alignLabelWithHint: true,
      helperText: kind == SaveKind.note
          ? null
          : 'Your personal notes stay separate.',
      helperMaxLines: 2,
      counterText: '',
    ),
    onChanged: (_) => setState(() {
      if (body.text.trim().isEmpty) extract = false;
    }),
  );
}
