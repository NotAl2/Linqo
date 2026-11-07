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
import 'ui/support_prompt.dart';
import 'library/support_prompt_policy.dart';
import 'services/diagnostics.dart';
import 'services/local_notifications.dart';
import 'ui/save_detail.dart';
import 'ui/welcome_screen.dart';
import 'ui/settings_screen.dart';
import 'services/weekly_updates.dart';
import 'ui/update_prompt.dart';

class _SupportNavigation extends NavigatorObserver {
  _SupportNavigation(this.changed);
  final VoidCallback changed;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => changed();
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Diagnostics.instance.initialize();
  FlutterError.onError = (details) {
    Diagnostics.instance.record(
      'flutter.error',
      error: details.exception,
      stack: details.stack,
      notify: false,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Diagnostics.instance.recordFatal(
      'dart.uncaught',
      error: error,
      stack: stack,
    );
    return false;
  };
  Diagnostics.instance.record('app.started');
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
  const LinqoApp({
    super.key,
    this.controller,
    this.enableSharing,
    this.enableSupportPrompts,
    this.enableOnboarding,
  });
  final LibraryController? controller;
  final bool? enableSharing;
  final bool? enableSupportPrompts;
  final bool? enableOnboarding;
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
  Timer? _supportTimer;
  int _lastSaveEpoch = 0;
  bool _supportPending = false, _supportShown = false, _showingSupport = false;
  bool _foreground = true;
  bool _onboarding = false;
  bool _openingNotification = false;
  WeeklyUpdates? _weeklyUpdates;
  Timer? _updateTimer;
  bool _checkingUpdates = false, _showingUpdate = false;
  late final _supportNavigation = _SupportNavigation(() {
    _scheduleSupport();
    unawaited(_checkNotificationOpen());
    _scheduleUpdates();
  });
  bool get _supportEnabled =>
      widget.enableSupportPrompts ?? widget.controller == null;
  bool get _sharing =>
      Platform.isAndroid && (widget.enableSharing ?? widget.controller == null);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_sharing) _shares.listen(() => unawaited(_checkShares()));
    if (widget.controller == null) {
      LocalNotifications.instance.listen(
        () => unawaited(_checkNotificationOpen()),
      );
    }
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
      _onboarding =
          (widget.enableOnboarding ?? widget.controller == null) &&
          await c.store.preference('onboarding_completed') != '1' &&
          c.total == 0 &&
          await c.store.preference('theme') == null;
      controller = c;
      if (widget.controller == null) _weeklyUpdates = WeeklyUpdates(c.store);
      mode = c.theme;
      c.addListener(_themeChanged);
      c.lab.addListener(_scheduleSupport);
      c.download.addListener(_scheduleSupport);
      setState(() => error = null);
      _scheduleUpdates();
      if (widget.controller == null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_checkNotificationOpen()),
        );
      }
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
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _scheduleSupport();
      unawaited(_checkNotificationOpen());
      _scheduleUpdates();
    } else {
      _supportTimer?.cancel();
      _updateTimer?.cancel();
    }
    if (state == AppLifecycleState.resumed && _sharing) {
      unawaited(_checkShares());
    }
  }

  Future<void> _checkShares() async {
    if (!mounted ||
        !_sharing ||
        _onboarding ||
        controller == null ||
        _showingSupport ||
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
    } catch (e, s) {
      Diagnostics.instance.record('sharing.failed', error: e, stack: s);
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

  Future<void> _checkNotificationOpen() async {
    final nav = _navigator.currentState, c = controller;
    if (!mounted ||
        widget.controller != null ||
        !_foreground ||
        _onboarding ||
        _openingNotification ||
        _drainingShares ||
        nav == null ||
        c == null) {
      return;
    }
    _openingNotification = true;
    try {
      final id = await LocalNotifications.instance.takeOpenSave();
      if (id == null || !mounted) return;
      final item = await c.store.get(id);
      if (!mounted) return;
      if (item == null) {
        ScaffoldMessenger.maybeOf(_navigator.currentContext!)?.showSnackBar(
          const SnackBar(
            content: Text('This save is no longer in your library.'),
          ),
        );
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(
        nav.push<void>(
          MaterialPageRoute(
            builder: (_) => SaveDetail(controller: c, id: id),
          ),
        ),
      );
      _openingNotification = false;
      if (mounted) unawaited(_checkNotificationOpen());
    } catch (_) {
      Diagnostics.instance.record('notifications.open_failed');
    } finally {
      _openingNotification = false;
    }
  }

  void _themeChanged() {
    if (mounted && controller!.theme != mode) {
      setState(() => mode = controller!.theme);
    }
    _scheduleSupport();
    _scheduleUpdates();
  }

  bool get _quietForUpdate {
    final c = controller, nav = _navigator.currentState;
    return mounted &&
        c != null &&
        nav != null &&
        _foreground &&
        !_onboarding &&
        !_openingNotification &&
        !_drainingShares &&
        !_showingSupport &&
        !_showingUpdate &&
        !nav.canPop() &&
        !c.processing &&
        !c.lab.busy &&
        !c.download.busy &&
        !c.hasPreviewWork &&
        View.of(nav.context).viewInsets.bottom == 0;
  }

  void _scheduleUpdates() {
    if (_weeklyUpdates == null ||
        !_foreground ||
        _checkingUpdates ||
        _showingUpdate) {
      return;
    }
    _updateTimer?.cancel();
    _updateTimer = Timer(
      const Duration(seconds: 4),
      () => unawaited(_maybeUpdate()),
    );
  }

  Future<void> _maybeUpdate() async {
    final updates = _weeklyUpdates;
    if (updates == null || !_quietForUpdate || _checkingUpdates) return;
    _checkingUpdates = true;
    try {
      await updates.poll();
      final release = await updates.pending();
      if (release == null || !_quietForUpdate) return;
      if (!await updates.claim(release) || !_quietForUpdate) return;
      _showingUpdate = true;
      await showDialog<void>(
        context: _navigator.currentContext!,
        builder: (_) => UpdatePrompt(release: release),
      );
    } catch (_) {
      /* Optional update checks never interrupt the library. */
    } finally {
      _showingUpdate = false;
      _checkingUpdates = false;
    }
  }

  void _scheduleSupport() {
    final c = controller;
    if (!mounted || !_supportEnabled || c == null || _supportShown) {
      return;
    }
    if (c.supportSaveEpoch != _lastSaveEpoch) {
      _lastSaveEpoch = c.supportSaveEpoch;
      _supportPending = true;
    }
    _supportTimer?.cancel();
    if (_supportPending && _foreground && !_showingSupport) {
      _supportTimer = Timer(
        const Duration(seconds: 2),
        () => unawaited(_maybeSupport()),
      );
    }
  }

  Future<void> _maybeSupport() async {
    final c = controller;
    final nav = _navigator.currentState;
    if (!mounted ||
        c == null ||
        nav == null ||
        !_foreground ||
        _supportShown ||
        _showingSupport ||
        _showingUpdate ||
        !_supportPending) {
      return;
    }
    if (_onboarding ||
        nav.canPop() ||
        _drainingShares ||
        c.processing ||
        c.lab.busy ||
        c.download.busy ||
        c.hasPreviewWork ||
        View.of(nav.context).viewInsets.bottom > 0) {
      _scheduleSupport();
      return;
    }
    _showingSupport = true;
    try {
      final policy = SupportPromptPolicy(c.store.db);
      if (!await policy.claim()) {
        _supportPending = false;
        return;
      }
      if (!mounted ||
          !_foreground ||
          nav.canPop() ||
          c.processing ||
          c.lab.busy ||
          c.download.busy ||
          c.hasPreviewWork) {
        return;
      }
      _supportShown = true;
      _supportPending = false;
      await showDialog<void>(
        context: nav.context,
        builder: (_) => SupportPrompt(policy: policy),
      );
    } catch (_) {
      // Optional support must never interrupt saving or opening the library.
      _supportPending = false;
    } finally {
      _showingSupport = false;
      if (mounted && _sharing) unawaited(_checkShares());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_sharing) _shares.dispose();
    if (widget.controller == null) {
      LocalNotifications.instance.disposeListener();
    }
    _supportTimer?.cancel();
    _updateTimer?.cancel();
    controller?.lab.removeListener(_scheduleSupport);
    controller?.download.removeListener(_scheduleSupport);
    controller?.removeListener(_themeChanged);
    if (widget.controller == null) controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    navigatorObservers: [_supportNavigation],
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
        ? _onboarding
              ? WelcomeScreen(
                  controller: controller!,
                  onDone: (setup) async {
                    await controller!.store.setPreference(
                      'onboarding_completed',
                      '1',
                    );
                    if (!mounted) return;
                    setState(() => _onboarding = false);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _scheduleUpdates();
                      unawaited(_checkNotificationOpen());
                      if (setup) {
                        _navigator.currentState!
                            .push<void>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    SettingsScreen(controller: controller!),
                              ),
                            )
                            .then((_) {
                              if (mounted && _sharing) {
                                unawaited(_checkShares());
                              }
                            });
                      } else if (_sharing) {
                        unawaited(_checkShares());
                      }
                    });
                  },
                )
              : LibraryShell(controller: controller!)
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
