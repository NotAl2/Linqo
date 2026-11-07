import 'package:flutter/material.dart';
import '../library/library_controller.dart';
import '../services/cloud_config.dart';
import '../services/cloud_services.dart';
import '../services/drive_backup.dart';
import '../services/tiers.dart';
import 'components.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.controller});
  final LibraryController controller;
  Future<void> _act(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String content,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(content)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _restore(BuildContext context, CloudServices cloud) async {
    var rows = <DriveSnapshot>[];
    await cloud.run(() async {
      rows = await cloud.drive.list();
    });
    if (!context.mounted) return;
    if (rows.isEmpty) {
      message(context, 'No Linqo backups found in this Drive account.');
      return;
    }
    final selected = await showModalBottomSheet<DriveSnapshot>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Choose a backup',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Restoring merges saves into this library. It does not replace your current content.',
              ),
              const SizedBox(height: 16),
              for (final row in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    DateTime.tryParse(
                          row.created,
                        )?.toLocal().toString().split('.').first ??
                        row.created,
                  ),
                  subtitle: Text(
                    '${(row.bytes / 1000000).toStringAsFixed(1)} MB',
                  ),
                  trailing: const Icon(Icons.restore_rounded),
                  onTap: () => Navigator.pop(context, row),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null &&
        context.mounted &&
        await _confirm(
          context,
          'Restore this backup?',
          'Its saves and collections will be merged with your library, even if the restored library exceeds your tier limit. Existing saves will be preserved.',
          'Restore',
        )) {
      await cloud.restoreSnapshot(selected);
      if (context.mounted) {
        message(context, 'Backup restored. Your current saves were preserved.');
      }
    }
  }

  Future<void> _history(BuildContext context, CloudServices cloud) async {
    var rows = <dynamic>[];
    int? cursor;
    await cloud.run(() async {
      final response = await cloud.api.call('/samples');
      rows = response['samples'] as List;
      cursor = response['next_cursor'] as int?;
    });
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ContributionHistory(
          cloud: cloud,
          initial: rows,
          nextCursor: cursor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloud = controller.cloud;
    if (cloud == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account & backup')),
        body: const Center(
          child: Text('Open Settings again after the library is ready.'),
        ),
      );
    }
    return AnimatedBuilder(
      animation: cloud,
      builder: (context, _) {
        final signedIn = cloud.identity.uid != null;
        final disabled = cloud.busy || !cloud.initialized;
        return Scaffold(
          appBar: AppBar(title: const Text('Account & backup')),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    Text(
                      signedIn
                          ? 'Your library. Your choice.'
                          : 'A little home, on this device.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      signedIn
                          ? cloud.identity.email ?? 'Signed in with Google'
                          : 'Keep using Linqo without an account. Sign in only when you want Drive backup or a paid tier.',
                    ),
                    const SizedBox(height: 16),
                    if (!CloudConfig.identityReady)
                      const Text(
                        'Google sign-in is not configured in this preview. Your local library and ZIP backups still work.',
                      ),
                    if (!signedIn)
                      FilledButton.icon(
                        onPressed: disabled || !CloudConfig.identityReady
                            ? null
                            : () => _act(context, cloud.signIn),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Continue with Google'),
                      ),
                    if (signedIn)
                      TextButton(
                        onPressed: disabled
                            ? null
                            : () => _act(context, cloud.signOut),
                        child: const Text('Sign out · keep local saves'),
                      ),
                    if (signedIn)
                      TextButton(
                        onPressed: disabled || !CloudConfig.backendReady
                            ? null
                            : () => _act(context, () async {
                                if (!await _confirm(
                                  context,
                                  'Delete your Linqo account?',
                                  'This deletes your Firebase account and retained contributions, and disconnects Drive. Local saves and existing Drive backups stay yours. Minimal purchase records are retained for refunds and restoration with the same Google account. You may need to sign out and sign in again first if Google requires recent authentication.',
                                  'Delete account',
                                )) {
                                  return;
                                }
                                await cloud.deleteAccount();
                              }),
                        child: const Text('Delete account'),
                      ),
                    if (cloud.busy) ...[
                      const SizedBox(height: 12),
                      if (!MediaQuery.disableAnimationsOf(context))
                        const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(cloud.status.isEmpty ? 'Connecting…' : cloud.status),
                    ],
                    if (cloud.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          cloud.error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                    Text(
                      'Room for your discoveries',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current tier: ${cloud.tier.name.toUpperCase()} · ${controller.total} saves · ${controller.collections.length} collections',
                    ),
                    if (!CloudConfig.limitsEnabled)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Unlimited development preview. Paid limits stay off until purchasing and restoration are verified. Checkout is available only in separately configured acceptance builds.',
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Free · 50 saves and 5 collections\nBuilt-in English AI and backups remain free.',
                    ),
                    const Divider(height: 28),
                    _TierRow(
                      tier: AppTier.xl,
                      title: 'XL · US\$5 once',
                      description: '150 saves · 30 collections',
                      cloud: cloud,
                      action: () => _act(context, () => cloud.buy(AppTier.xl)),
                    ),
                    const Divider(height: 28),
                    _TierRow(
                      tier: AppTier.xxl,
                      title: 'XXL · US\$10 once',
                      description:
                          'Unlimited saves and collections · import compatible custom models',
                      cloud: cloud,
                      action: () => _act(context, () => cloud.buy(AppTier.xxl)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'XL → XXL is a separate US\$10 purchase. Donations through Buy Me a Coffee do not unlock a tier. Future customization is not available yet.',
                    ),
                    if (signedIn)
                      TextButton.icon(
                        onPressed: disabled || !CloudConfig.backendReady
                            ? null
                            : () => _act(
                                context,
                                () => cloud.run(cloud.restorePurchase),
                              ),
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Restore purchase'),
                      ),
                    const SizedBox(height: 28),
                    Text(
                      'A spare copy, in your Drive',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Optional backup and restore, not live sync. Saves, notes, collections, extracted details and file copies use your Google storage. Models and credentials are excluded. Google protects stored data; these are not end-to-end encrypted backups.',
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Drive backup'),
                      subtitle: const Text(
                        'Daily when open, idle and on Wi-Fi · three snapshots per device',
                      ),
                      value: cloud.driveEnabled,
                      onChanged: disabled || !signedIn
                          ? null
                          : (value) => _act(context, () async {
                              if (value &&
                                  !await _confirm(
                                    context,
                                    'Back up this library to Drive?',
                                    'This uploads your current local library and private file copies to ${cloud.identity.email}. Signing in alone does not upload anything.',
                                    'Enable backup',
                                  )) {
                                return;
                              }
                              await cloud.enableDrive(value);
                            }),
                    ),
                    Text(
                      cloud.lastBackup == null
                          ? 'No successful Drive backup yet.'
                          : 'Last backup: ${DateTime.tryParse(cloud.lastBackup!)?.toLocal().toString().split('.').first ?? cloud.lastBackup}',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: disabled || !cloud.driveEnabled
                              ? null
                              : () => _act(context, cloud.backupNow),
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Back up now'),
                        ),
                        TextButton.icon(
                          onPressed: disabled || !cloud.driveEnabled
                              ? null
                              : () => _act(
                                  context,
                                  () => _restore(context, cloud),
                                ),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Restore from Drive'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Help Linqo learn, optionally',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Share small English public-source excerpts and their extraction results for review. Personal notes and files are excluded. Filtering cannot guarantee anonymity. No training happens on your phone.',
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Contribute automatic samples'),
                      subtitle: const Text(
                        'Off by default · at most two daily · Wi-Fi and idle only',
                      ),
                      value: cloud.contributions,
                      onChanged:
                          disabled || !signedIn || !CloudConfig.backendReady
                          ? null
                          : (value) => _act(context, () async {
                              if (value &&
                                  !await _confirm(
                                    context,
                                    'Share examples to improve Linqo?',
                                    'Eligible source excerpts and model results will leave your device. We remove obvious identifiers, but cannot guarantee anonymity. Server samples expire after 30 days; unreviewed maintainer copies after 90 days. You can inspect and delete contributions. Deleting an example cannot undo its influence on an already trained model.',
                                    'I agree',
                                  )) {
                                return;
                              }
                              await cloud.setContributions(value);
                            }),
                    ),
                    if (signedIn)
                      TextButton.icon(
                        onPressed: disabled || !CloudConfig.backendReady
                            ? null
                            : () =>
                                  _act(context, () => _history(context, cloud)),
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('View or delete contributions'),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Local ZIP export/import remains available in Settings without an account. Keep important originals and a backup outside Linqo.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.title,
    required this.description,
    required this.cloud,
    required this.action,
  });
  final AppTier tier;
  final String title, description;
  final CloudServices cloud;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(description),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed:
            cloud.busy ||
                !CloudConfig.checkoutEnabled ||
                !cloud.paymentsLive ||
                cloud.identity.uid == null ||
                cloud.tier.index >= tier.index
            ? null
            : action,
        child: Text(
          cloud.tier == tier
              ? 'Your tier'
              : 'Choose ${tier.name.toUpperCase()}',
        ),
      ),
    ],
  );
}

class _ContributionHistory extends StatefulWidget {
  const _ContributionHistory({
    required this.cloud,
    required this.initial,
    this.nextCursor,
  });
  final CloudServices cloud;
  final List<dynamic> initial;
  final int? nextCursor;
  @override
  State<_ContributionHistory> createState() => _ContributionHistoryState();
}

class _ContributionHistoryState extends State<_ContributionHistory> {
  late final rows = List<dynamic>.from(widget.initial);
  late int? cursor = widget.nextCursor;
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your contributions')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Automatic results need review before training. Expired samples are removed from the server. Deletion requests are applied to maintainer copies at the next dataset pull.',
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty) const Text('No retained contributions.'),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['sample']?['category'] ?? 'Expired sample'} · ${DateTime.fromMillisecondsSinceEpoch(row['created'] as int).toLocal().toString().split('.').first}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    row['sample']?['source'] as String? ??
                        'Source text expired from the server. You can still request deletion of maintainer copies.',
                  ),
                  const SizedBox(height: 8),
                  if (row['sample'] != null)
                    SelectableText(row['sample']['output'] as String),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              await widget.cloud.api.call(
                                '/samples/${Uri.encodeComponent(row['id'] as String)}',
                                method: 'DELETE',
                              );
                              if (mounted) setState(() => rows.remove(row));
                            } catch (e) {
                              if (context.mounted) message(context, e);
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete contribution'),
                  ),
                  const Divider(),
                ],
              ),
            ),
          if (cursor != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final response = await widget.cloud.api.call(
                          '/samples?before=$cursor',
                        );
                        if (mounted) {
                          setState(() {
                            rows.addAll(response['samples'] as List);
                            cursor = response['next_cursor'] as int?;
                          });
                        }
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: const Text('Load older contributions'),
            ),
        ],
      ),
    ),
  );
}
