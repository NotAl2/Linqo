import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PolicyScreen extends StatefulWidget {
  const PolicyScreen({super.key, required this.title, required this.asset});
  final String title, asset;
  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  late final content = rootBundle.loadString(widget.asset);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<String>(
      future: content,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: SelectableText(
                'Could not open this notice. Contact aryandurgude123@gmail.com.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final block
                  in snapshot.data!.replaceAll('\r\n', '\n').split('\n\n'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    block
                        .replaceAll(RegExp(r'^#+ '), '')
                        .replaceAll('**', '')
                        .replaceAll('`', '')
                        .replaceAllMapped(
                          RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
                          (m) => '${m[1]} (${m[2]})',
                        ),
                    style: block.startsWith('#')
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
