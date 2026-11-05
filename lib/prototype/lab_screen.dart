import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lab_controller.dart';

const englishSample = '''Creamy chickpea skillet
Ingredients: 1 onion, 3 cloves garlic, 1 can chickpeas, 200 ml coconut milk, spinach.
Dice the onion and mince the garlic.
Sauté the onion and garlic, then add chickpeas and coconut milk.
Simmer for 10 minutes. Stir in the spinach.
Serve with rice.''';
const hindiSample = '''चना सलाद
सामग्री: 1 कप उबले चने, 1 टमाटर, 1 प्याज़, नींबू का रस।
टमाटर और प्याज़ को छोटे टुकड़ों में काटें।
चने, टमाटर और प्याज़ मिलाएँ।
नींबू का रस डालकर परोसें।''';
const placesSample = '''Weekend ideas in London
Try a coffee at Monmouth Coffee in Borough Market.
Visit the Tate Modern on Bankside.
Walk along the South Bank in the afternoon.
No opening hours or booking details were provided.''';

class LabScreen extends StatefulWidget {
  const LabScreen({
    super.key,
    required this.controller,
    required this.themeMode,
    required this.onThemeChanged,
  });
  final LabController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> with WidgetsBindingObserver {
  final source = TextEditingController(text: englishSample);
  int taps = 0;
  bool _picking = false;
  LabController get lab => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    source.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(lab.releaseMemory());
    }
  }

  @override
  void didHaveMemoryPressure() => unawaited(lab.releaseMemory());

  Future<void> _import() async {
    if (_picking || lab.busy) return;
    setState(() => _picking = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf'],
        withData: false,
      );
      if (!mounted || selection == null) return;
      final file = selection.files.single;
      final path = file.path;
      if (path == null) {
        throw StateError(
          'The file provider did not provide a local model file.',
        );
      }
      await lab.importModel(path, file.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open the model: $e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: lab,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      return Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_rounded),
              SizedBox(width: 8),
              Text('Linqo', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          actions: [
            PopupMenuButton<ThemeMode>(
              tooltip: 'Appearance',
              initialValue: widget.themeMode,
              icon: const Icon(Icons.contrast_rounded),
              onSelected: widget.onThemeChanged,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: ThemeMode.system,
                  child: Text('Follow system'),
                ),
                PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
                PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;
              return SingleChildScrollView(
                padding: EdgeInsets.all(constraints.maxWidth < 380 ? 16 : 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Your saves.\nYour device.',
                          style: theme.textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Test Linqo’s local extraction engine before we build the full library.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _modelPanel(context),
                        const SizedBox(height: 24),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _sourcePanel(context)),
                              const SizedBox(width: 24),
                              Expanded(child: _resultPanel(context)),
                            ],
                          )
                        else ...[
                          _sourcePanel(context),
                          const SizedBox(height: 24),
                          _resultPanel(context),
                        ],
                        const SizedBox(height: 24),
                        _diagnosticsPanel(context),
                        const SizedBox(height: 24),
                        Text(
                          'Prototype scope: pasted text + local GGUF inference. Reels, OCR, audio, sharing, and the saved library come next.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );

  Widget _panel(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required List<Widget> children,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: const Color(0xFF201D22), size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );

  Widget _modelPanel(BuildContext context) => _panel(
    context,
    icon: Icons.memory_rounded,
    accent: const Color(0xFFAFDEC8),
    title: 'A small model, all yours',
    children: [
      Text(
        lab.model?.name ?? 'Start with Qwen3-1.7B · Q4_K_M',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        lab.model == null
            ? 'Download a compatible GGUF separately, then import it. Linqo copies the file to private storage and computes its SHA-256. Model weights are not bundled.'
            : '${(lab.model!.bytes / (1024 * 1024)).toStringAsFixed(0)} MB · private copy ready. ${lab.modelLoaded ? 'Loaded on CPU.' : 'Load to begin.'}',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: lab.busy || _picking ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(
              _picking
                  ? 'Opening…'
                  : lab.model == null
                  ? 'Import GGUF'
                  : 'Replace model',
            ),
          ),
          if (lab.model != null && !lab.modelLoaded)
            FilledButton.icon(
              onPressed: lab.busy ? null : lab.load,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Load model'),
            ),
          if (lab.modelLoaded)
            TextButton.icon(
              onPressed: lab.busy ? null : lab.unload,
              icon: const Icon(Icons.power_settings_new_rounded),
              label: const Text('Free model memory'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('CPU threads'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
            ],
            selected: {lab.threads},
            onSelectionChanged: lab.busy || lab.modelLoaded
                ? null
                : (value) => setState(() => lab.threads = value.single),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'CPU only · 2,048-token context · memory-saving cache',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (lab.phase == LabPhase.restoring ||
          lab.phase == LabPhase.importing ||
          lab.phase == LabPhase.loading ||
          lab.phase == LabPhase.unloading ||
          lab.phase == LabPhase.cancelling) ...[
        const SizedBox(height: 16),
        if (!MediaQuery.disableAnimationsOf(context))
          const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          lab.phase == LabPhase.restoring
              ? 'Checking your remembered model…'
              : lab.phase == LabPhase.cancelling
              ? 'Stopping safely…'
              : lab.phase == LabPhase.importing
              ? 'Copying and hashing model… Keep Linqo open.'
              : 'Updating model memory…',
        ),
        if (lab.phase == LabPhase.importing || lab.phase == LabPhase.loading)
          TextButton(onPressed: lab.cancel, child: const Text('Cancel')),
      ],
    ],
  );

  Widget _sourcePanel(BuildContext context) => _panel(
    context,
    icon: Icons.bookmark_border_rounded,
    accent: const Color(0xFFFFE58A),
    title: 'Something worth saving',
    children: [
      const Text(
        'Paste a caption, note, or transcript. The examples below are synthetic test fixtures.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _sampleChip('Recipe', englishSample),
          _sampleChip('हिन्दी', hindiSample),
          _sampleChip('Places', placesSample),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: source,
        enabled: !lab.busy,
        minLines: 7,
        maxLines: 14,
        maxLength: 30000,
        decoration: const InputDecoration(
          labelText: 'Source text',
          alignLabelWithHint: true,
          hintText: 'What would you like to remember?',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: lab.canExtract
                ? () {
                    FocusScope.of(context).unfocus();
                    lab.extract(source.text);
                  }
                : null,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Extract on device'),
          ),
          if (lab.phase == LabPhase.extracting ||
              lab.phase == LabPhase.cancelling)
            OutlinedButton.icon(
              onPressed: lab.phase == LabPhase.cancelling ? null : lab.cancel,
              icon: const Icon(Icons.stop_rounded),
              label: Text(
                lab.phase == LabPhase.cancelling
                    ? 'Stopping…'
                    : 'Stop extraction',
              ),
            ),
        ],
      ),
      if (!lab.modelLoaded) ...[
        const SizedBox(height: 8),
        const Text('Import and load a model to enable extraction.'),
      ],
    ],
  );

  Widget _sampleChip(String title, String text) => ActionChip(
    label: Text(title),
    onPressed: lab.busy ? null : () => setState(() => source.text = text),
  );

  Widget _resultPanel(BuildContext context) {
    final result = lab.result;
    return _panel(
      context,
      icon: Icons.notes_rounded,
      accent: const Color(0xFFA9DDEB),
      title: 'The useful part',
      children: [
        if (lab.error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              lab.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (lab.phase == LabPhase.extracting ||
            lab.phase == LabPhase.cancelling) ...[
          if (!MediaQuery.disableAnimationsOf(context))
            const LinearProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            'Reading your source locally… You can still scroll and use the responsiveness check below.',
          ),
        ] else if (result != null) ...[
          Text(result.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(result.summary, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(
            '${result.type} · ${result.facts.length} evidence-linked details',
          ),
          const SizedBox(height: 8),
          const Text(
            'Details keep the original source text. The summary is AI-generated; review the original to confirm meaning.',
          ),
          if (result.isPartial) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                'Needs review',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final warning in result.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(warning),
              ),
          ],
          const SizedBox(height: 12),
          for (final fact in result.facts)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              title: Text(
                fact.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(fact.value),
              children: [
                for (final id in fact.lineIds)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        '[$id] ${lab.evidence!.lines[id - 1].text}',
                      ),
                    ),
                  ),
              ],
            ),
          if (result.additionalSource.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('More from the source'),
              children: [
                for (final line in result.additionalSource)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SelectableText('[${line.id}] ${line.text}'),
                    ),
                  ),
              ],
            ),
        ] else if (lab.phase == LabPhase.cancelled)
          const Text(
            'Extraction stopped. Your source is still here; run it again whenever you’re ready.',
          )
        else if (lab.error == null) ...[
          Icon(
            Icons.link_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Less rewatching.\nMore remembering.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Your summary and source-linked details will appear here after a real local inference run. Missing information stays missing.',
          ),
        ],
        if (lab.rawOutput.isNotEmpty) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Raw model response'),
            children: [SelectableText(lab.rawOutput)],
          ),
        ],
      ],
    );
  }

  Widget _diagnosticsPanel(BuildContext context) {
    final report = lab.report;
    return _panel(
      context,
      icon: Icons.speed_rounded,
      accent: const Color(0xFFF2B9B4),
      title: 'Does it still feel fast?',
      children: [
        const Text(
          'Scroll, switch themes, and tap while extraction runs. Measure performance in a profile build on your phone.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => taps++),
              icon: const Icon(Icons.touch_app_outlined),
              label: Text('Tap check · $taps'),
            ),
            Text(
              kProfileMode
                  ? 'Profile build'
                  : kReleaseMode
                  ? 'Release build'
                  : 'Debug build · timings are not a benchmark',
            ),
          ],
        ),
        if (report != null) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _measurement(
                context,
                'Elapsed',
                '${(report.elapsedMs / 1000).toStringAsFixed(1)} s',
              ),
              _measurement(
                context,
                'First output',
                report.firstOutputMs == null
                    ? 'Not received'
                    : '${(report.firstOutputMs! / 1000).toStringAsFixed(1)} s',
              ),
              _measurement(
                context,
                'UI p95',
                report.uiP95Ms == null
                    ? 'No samples'
                    : '${report.uiP95Ms!.toStringAsFixed(1)} ms',
              ),
              _measurement(
                context,
                'Raster p95',
                report.rasterP95Ms == null
                    ? 'No samples'
                    : '${report.rasterP95Ms!.toStringAsFixed(1)} ms',
              ),
              _measurement(
                context,
                'Frames > 16.7 ms',
                '${report.overBudgetFrames} / ${report.frames}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Frame timings sample active rendered frames only. They do not measure touch latency, RAM, thermal behavior, or tokens per second.',
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: lab.diagnosticsJson()));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Diagnostics copied. Source text is excluded.'),
                ),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy diagnostics'),
        ),
      ],
    );
  }

  Widget _measurement(BuildContext context, String label, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      );
}
