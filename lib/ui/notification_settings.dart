import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_notifications.dart';
import 'components.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool loading = true, changing = false;
  Map<String, dynamic> status = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final value = await LocalNotifications.instance.status();
    if (mounted) {
      setState(() {
        status = value;
        loading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> enable(bool value) async {
    setState(() => changing = true);
    final enabled = await LocalNotifications.instance.setEnabled(value);
    await refresh();
    if (!mounted) return;
    setState(() => changing = false);
    if (value && !enabled) {
      message(
        context,
        'Notifications are blocked. You can allow them in Android notification settings.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = status['available'] == true,
        allowed = status['allowed'] == true,
        enabled = status['enabled'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'A little heads-up',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Get a local notification when extraction finishes or needs attention. No server, account or internet connection is needed.',
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Extraction notifications'),
              subtitle: Text(
                loading
                    ? 'Checking permission…'
                    : !available
                    ? 'Available on Android builds.'
                    : enabled && allowed
                    ? 'Completion and error alerts are on.'
                    : enabled
                    ? 'Blocked by Android. Open notification settings below.'
                    : 'Off. Enable when you want result alerts.',
              ),
              value: enabled,
              onChanged: loading || changing || !available ? null : enable,
            ),
            if (available) ...[
              OutlinedButton.icon(
                onPressed: enabled && allowed && !changing
                    ? () async {
                        final sent = await LocalNotifications.instance.show(
                          test: true,
                        );
                        if (context.mounted) {
                          message(
                            context,
                            sent
                                ? 'Test notification sent. Check your notification shade.'
                                : 'Android blocked the notification. Check notification settings.',
                          );
                        }
                        await refresh();
                      }
                    : null,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Send test notification'),
              ),
              TextButton(
                onPressed: () => LocalNotifications.instance.settings(),
                child: const Text('Android notification settings'),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Your saved titles, captions and URLs stay out of notifications. Tapping a result opens that save. Only the latest result notification is retained.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Keep Linqo open while extracting. Work pauses when the app goes into the background; stopped or cancelled jobs do not send error alerts. This setting does not enable background processing.',
            ),
          ],
        ),
      ),
    );
  }
}
