import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_version.dart';
import '../services/diagnostics.dart';
import '../services/update_checker.dart';
import 'components.dart';

class ReleaseSettings extends StatefulWidget {
  const ReleaseSettings({super.key});
  @override
  State<ReleaseSettings> createState() => _ReleaseSettingsState();
}

class _ReleaseSettingsState extends State<ReleaseSettings> {
  bool busy = false, previews = true;
  int taps = 0;
  DateTime? lastTap;
  String? status;
  AvailableRelease? release;
  Future<void> check() async {
    setState(() {
      busy = true;
      status = null;
      release = null;
    });
    try {
      final found = await UpdateChecker().check(
        linqoVersion,
        previews: previews,
      );
      if (mounted) {
        setState(() {
          release = found;
          status = found == null
              ? 'You’re up to date for this release channel.'
              : '${found.version}${found.preview ? ' preview' : ''} is available.';
        });
      }
      Diagnostics.instance.record('updates.checked');
    } catch (e, s) {
      Diagnostics.instance.record('updates.failed', error: e, stack: s);
      if (mounted) {
        setState(
          () => status =
              'Could not reach GitHub. Your library still works offline. Try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 28),
      Text('About & updates', style: Theme.of(context).textTheme.titleLarge),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Linqo $linqoVersion'),
        subtitle: const Text('Active development · build $linqoBuild'),
        onTap: () {
          final now = DateTime.now();
          if (lastTap == null ||
              now.difference(lastTap!) > const Duration(seconds: 3)) {
            taps = 0;
          }
          lastTap = now;
          if (++taps == 7) {
            taps = 0;
            openPage(context, const DiagnosticsScreen());
          }
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Include preview releases'),
        value: previews,
        onChanged: busy ? null : (v) => setState(() => previews = v),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : check,
        icon: const Icon(Icons.system_update_outlined),
        label: Text(busy ? 'Checking GitHub…' : 'Check for updates'),
      ),
      if (status != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(status!, semanticsLabel: status),
        ),
      if (release != null)
        TextButton(
          onPressed: () async {
            try {
              if (!await launchUrl(
                release!.page,
                mode: LaunchMode.externalApplication,
              )) {
                throw StateError('Browser unavailable');
              }
            } catch (_) {
              if (context.mounted) {
                message(
                  context,
                  'Could not open GitHub. Visit github.com/NotAl2/Linqo/releases.',
                );
              }
            }
          },
          child: const Text('View release on GitHub'),
        ),
      const Text(
        'Checks run only when you tap. Updates open on GitHub; Linqo never installs an APK silently.',
      ),
    ],
  );
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool exporting = false;
  Future<void> export() async {
    setState(() => exporting = true);
    Directory? work;
    try {
      work = await Directory(
        '${(await getTemporaryDirectory()).path}/library-backups',
      ).create(recursive: true);
      work = await work.createTemp('diagnostics-');
      final bytes = utf8.encode(Diagnostics.instance.export());
      final zip = ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile('diagnostics.json', bytes.length, bytes)),
      );
      final file = await File('${work.path}/diagnostics.zip').writeAsBytes(zip);
      if (Platform.isAndroid) {
        await const MethodChannel('dev.linqo/backup').invokeMethod<String>(
          'save',
          {'path': file.path, 'name': 'Linqo-diagnostics.zip'},
        );
      } else {
        if (mounted) {
          message(
            context,
            'Diagnostic export is currently available on Android.',
          );
        }
      }
    } catch (_) {
      if (mounted) message(context, 'Could not export diagnostics. Try again.');
    } finally {
      if (work != null) await work.delete(recursive: true);
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local diagnostics')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: Diagnostics.instance,
        builder: (context, _) {
          final d = Diagnostics.instance;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Opt-in troubleshooting. No analytics or automatic uploads. Records event codes, error types and Linqo stack locations, without saved text, URLs, file paths or exception messages. Native process crashes may not be captured.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep local diagnostic logs'),
                subtitle: const Text(
                  'Up to 100 events. Turning off also clears logs.',
                ),
                value: d.enabled,
                onChanged: (v) => unawaited(d.setEnabled(v)),
              ),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: exporting ? null : export,
                    child: const Text('Export logs'),
                  ),
                  TextButton(
                    onPressed: () => d.clear(),
                    child: const Text('Clear logs'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (d.events.isEmpty) const Text('No recorded events.'),
              for (final e in d.events.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e['code'] as String? ?? 'event'),
                  subtitle: Text('${e['time']}\n${e['type'] ?? ''}'),
                ),
            ],
          );
        },
      ),
    ),
  );
}
