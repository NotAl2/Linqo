import 'dart:io';
import 'package:flutter/material.dart';
import '../sharing/link_preview.dart';

/// Local-only image decoding with bounded dimensions. Never fetches on scroll.
class SavedPreviewImage extends StatefulWidget {
  const SavedPreviewImage({
    super.key,
    required this.name,
    required this.fallback,
  });
  final String name;
  final Widget fallback;
  @override
  State<SavedPreviewImage> createState() => _SavedPreviewImageState();
}

class _SavedPreviewImageState extends State<SavedPreviewImage> {
  // Only file handles, not image bytes. Avoid a fallback frame when filters
  // remount an already decoded cover. Missing/evicted files still use errorBuilder.
  static final _resolved = <String, File>{};
  late Future<File?> file = PreviewCache.file(widget.name);
  @override
  void didUpdateWidget(SavedPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) file = PreviewCache.file(widget.name);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: file,
    initialData: _resolved[widget.name],
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (value == null) return widget.fallback;
      _resolved[widget.name] = value;
      if (_resolved.length > 80) _resolved.remove(_resolved.keys.first);
      return Image.file(
        value,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 512,
        gaplessPlayback: false,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    },
  );
}
