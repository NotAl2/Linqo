import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'library/library_controller.dart';
import 'library/library_store.dart';
import 'ui/library_shell.dart';
import 'theme.dart';
import 'sharing/shared_content.dart';
import 'ui/save_editor.dart';
import 'ui/brand.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Linqo',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Fredoka',
    ], await rootBundle.loadString('assets/fonts/fredoka-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/nunito-OFL.txt'));
  });
  PaintingBinding.instance.imageCache
    ..maximumSize = 64
    ..maximumSizeBytes = 24 * 1024 * 1024;
  runApp(const LinqoApp());
}

class LinqoApp extends StatefulWidget {
  const LinqoApp({super.key, this.controller, this.enableSharing});
  final LibraryController? controller;
  final bool? enableSharing;
  @override
  State<LinqoApp> createState() => _LinqoAppState();
}

class _LinqoAppState extends State<LinqoApp> with WidgetsBindingObserver {
  LibraryController? controller;
  ThemeMode mode = ThemeMode.system;
  String? error;
  final _navigator = GlobalKey<NavigatorState>();
  final _shares = AndroidShareInbox();
  bool _drainingShares = false, _shareWakeAgain = false;
  bool get _sharing =>
      Platform.isAndroid && (widget.enableSharing ?? widget.controller == null);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_sharing) _shares.listen(() => unawaited(_checkShares()));
    unawaited(_open());
  }

  Future<void> _open() async {
    final entry = Stopwatch()..start();
    try {
      final c =
          widget.controller ?? LibraryController(await LibraryStore.open());
      if (widget.controller == null) await c.initialize();
      // Database work runs concurrently with one short branded entry, not an
      // extra splash route. Accessibility and injected test controllers skip it.
      if (widget.controller == null &&
          !WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations &&
          entry.elapsedMilliseconds < 220) {
        await Future<void>.delayed(
          Duration(milliseconds: 220 - entry.elapsedMilliseconds),
        );
      }
      if (!mounted) {
        c.dispose();
        return;
      }
      controller = c;
      mode = c.theme;
      c.addListener(_themeChanged);
      setState(() => error = null);
      if (_sharing) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_checkShares()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not open your library. Your data has not been reset. $e',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sharing) {
      unawaited(_checkShares());
    }
  }

  Future<void> _checkShares() async {
    if (!mounted ||
        !_sharing ||
        controller == null ||
        _navigator.currentState == null) {
      return;
    }
    if (_drainingShares) {
      _shareWakeAgain = true;
      return;
    }
    _drainingShares = true;
    try {
      while (mounted) {
        final shared = await _shares.peek();
        if (shared == null || !mounted) break;
        if (await controller!.store.receivedShare(shared.id) == null) {
          if (!mounted) break;
          await _navigator.currentState!.push<int>(
            MaterialPageRoute(
              builder: (_) =>
                  SaveEditor(controller: controller!, shared: shared),
            ),
          );
        }
        // A receipt in SQLite makes a crash between Save and ack idempotent.
        if (mounted) await _shares.acknowledge(shared.id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(_navigator.currentContext!)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the shared link. Reopen Linqo to try again.',
            ),
          ),
        );
      }
    } finally {
      _drainingShares = false;
      if (_shareWakeAgain && mounted) {
        _shareWakeAgain = false;
        unawaited(_checkShares());
      }
    }
  }

  void _themeChanged() {
    if (mounted && controller!.theme != mode) {
      setState(() => mode = controller!.theme);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_sharing) _shares.dispose();
    controller?.removeListener(_themeChanged);
    if (widget.controller == null) controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'Linqo',
    debugShowCheckedModeBanner: false,
    theme: linqoTheme(Brightness.light),
    darkTheme: linqoTheme(Brightness.dark),
    themeMode: mode,
    themeAnimationDuration:
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180),
    home: controller != null
        ? LibraryShell(controller: controller!)
        : error == null
        ? const LinqoSplash()
        : Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: error == null
                      ? const Text('Opening your library…')
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bookmarks_outlined, size: 40),
                            const SizedBox(height: 24),
                            Text(error!, textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _open,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
  );
}
