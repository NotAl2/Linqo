import 'dart:async';
import 'package:flutter/material.dart';
import '../prototype/lab_controller.dart';

class ExtractionProgressView extends StatefulWidget {
  const ExtractionProgressView({super.key, required this.lab});
  final LabController lab;
  @override
  State<ExtractionProgressView> createState() => _ExtractionProgressViewState();
}

class _ExtractionProgressViewState extends State<ExtractionProgressView> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.lab,
    builder: (context, _) {
      final lab = widget.lab, progress = widget.lab.progress;
      final extracting = lab.phase == LabPhase.extracting;
      final elapsed = lab.extractionElapsed.inSeconds;
      final eta = extracting
          ? progress.remainingSeconds(lab.extractionElapsed.inMilliseconds)
          : null;
      final completed = progress.completed;
      final part = lab.currentPart.clamp(1, progress.total.clamp(1, 64));
      final label = lab.phase == LabPhase.loading
          ? 'Loading the model…'
          : lab.phase == LabPhase.cancelling
          ? 'Stopping safely…'
          : !extracting
          ? 'Preparing or finishing your save…'
          : progress.total == 0
          ? 'Preparing the source…'
          : completed == progress.total
          ? 'Checking the final result…'
          : completed == 0
          ? 'Working on part $part of ${progress.total}'
          : 'Part $part of ${progress.total} · ${(100 * (progress.fraction ?? 0)).floor()}% checked';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: extracting && progress.total > 0 && completed > 0
                ? progress.fraction
                : MediaQuery.disableAnimationsOf(context)
                ? 0
                : null,
            semanticsLabel: label,
            borderRadius: BorderRadius.circular(4),
            minHeight: 5,
          ),
          if (extracting)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${elapsed}s elapsed · ${eta == null ? 'Time remaining is still being estimated' : 'about ${eta < 60 ? '${eta}s' : '${(eta / 60).ceil()} min'} left (estimate)'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );
    },
  );
}
