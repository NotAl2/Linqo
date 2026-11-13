import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../library/library_controller.dart';
import '../services/cloud_config.dart';
import '../services/cloud_services.dart';
import '../services/drive_backup.dart';
import '../services/tiers.dart';
import 'components.dart';
import 'checkout_dialog.dart';
import 'polar_sandbox_card.dart';
import 'policy_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.controller});
  final LibraryController controller;
  Future<void> _buy(
    BuildContext context,
    CloudServices cloud,
    AppTier tier,
  ) async {
    await _act(context, () async {
      final account = cloud.identity.uid;
      final sandbox = cloud.sandboxCheckout;
      final provider = cloud.paymentProvider;
      final quotedMinor = cloud.priceMinor(tier);
      final phone = await showDialog<String>(
        context: context,
        builder: (_) => CheckoutDialog(
          tier: tier,
          provider: provider,
          sandbox: sandbox,
          amountMinor: quotedMinor,
          accountLabel: cloud.identity.email ?? 'your signed-in Google account',
        ),
      );
      if (phone == null) return;
      if (cloud.identity.uid != account || cloud.paymentProvider != provider) {
        throw StateError('Account changed. Start checkout again.');
      }
      final purchase = await cloud.preparePurchase(tier, phone);
      if (purchase.sandbox != sandbox) {
        throw StateError('Checkout mode changed. Start checkout again.');
      }
      if (purchase.amountMinor != quotedMinor) {
        throw StateError(
          'The price changed. Refresh purchase details and try again.',
        );
      }
      await cloud.openPurchase(purchase);
    });
  }

  Future<void> _requestAccess(
    BuildContext context,
    CloudServices cloud, [
    AppTier? tier,
  ]) => _act(context, () async {
    if (cloud.identity.uid == null) {
      throw StateError(
        'Sign in with Google at the top of this screen before requesting access.',
      );
    }
    if (cloud.accountCode.isEmpty) await cloud.run(cloud.restorePurchase);
    if (cloud.accountCode.isEmpty) {
      throw StateError(
        'Could not load your account code. Reconnect and choose Get account code, then request access.',
      );
    }
    final subject = Uri.encodeComponent('Linqo prebuild access request');
    final body = Uri.encodeComponent(
      'Requested tier: ${tier?.name.toUpperCase() ?? ''}\nLinqo account code: ${cloud.accountCode}\n',
    );
    if (!await launchUrl(
      Uri.parse('mailto:aryandurgude123@gmail.com?subject=$subject&body=$body'),
    )) {
      throw StateError(
        'Could not open email. Contact aryandurgude123@gmail.com.',
      );
    }
  });

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
        final checkoutAvailable =
            CloudConfig.checkoutEnabled && cloud.paymentsLive;
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
                          : 'Keep using Linqo without an account. Sign in to request or restore full prebuild access. Backups through Files work without signing in.',
                    ),
                    const SizedBox(height: 16),
                    if (!CloudConfig.identityReady)
                      const Text(
                        'Google sign-in is not configured in this preview. Your local library and ZIP backups still work.',
                      ),
                    if (!signedIn) ...[
                      const Text(
                        'Connected features are for adults (18+). Review the notices before continuing. Google sign-in shares your account identity with Firebase; it does not upload your library.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => openPage(
                              context,
                              const PolicyScreen(
                                title: 'Privacy notice',
                                asset: 'policies/PRIVACY.md',
                              ),
                            ),
                            child: const Text('Privacy notice'),
                          ),
                          TextButton(
                            onPressed: () => openPage(
                              context,
                              const PolicyScreen(
                                title: 'Terms of use',
                                asset: 'policies/TERMS.md',
                              ),
                            ),
                            child: const Text('Terms of use'),
                          ),
                        ],
                      ),
                    ],
                    if (!signedIn)
                      FilledButton.icon(
                        onPressed: disabled || !CloudConfig.identityReady
                            ? null
                            : () => _act(context, cloud.signIn),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Continue with Google'),
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Room for your discoveries',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Current tier: ${cloud.tier.name.toUpperCase()} · ${controller.total} saves · ${controller.collections.length} collections',
                            ),
                            const SizedBox(height: 20),
                            _UsageMeter(
                              label: 'saves',
                              count: controller.total,
                              limit: cloud.limits.saves,
                            ),
                            const SizedBox(height: 16),
                            _UsageMeter(
                              label: 'collections',
                              count: controller.collections.length,
                              limit: cloud.limits.collections,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Your existing library stays safe. Reading, search, editing, extraction and backups remain available, even above a limit. Deleting content frees space.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'A little more room?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      checkoutAvailable
                          ? 'Upgrades use secure hosted checkout. Use the same Google account to restore access later.'
                          : 'Payments are paused for this prebuild. For XL or XXL access, email aryandurgude123@gmail.com with your requested tier and Linqo account code. Requests are reviewed manually; a donation does not automatically unlock access.',
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _requestAccess(context, cloud),
                      icon: const Icon(Icons.mail_outline_rounded),
                      label: const Text('Email for full prebuild access'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Free · 100 saves and 5 collections\nBasic local summarization and backups remain free.',
                    ),
                    if (cloud.paymentsLive && cloud.sandboxCheckout) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Sandbox checkout · test payments do not unlock paid tiers.',
                      ),
                    ],
                    const Divider(height: 28),
                    _TierRow(
                      tier: AppTier.xl,
                      title: cloud.paymentsLive ? 'XL · ₹449 once' : 'XL',
                      description:
                          '500 saves · 30 collections\nPlanned: enhanced summarization options, early app updates and early access to improved models.',
                      cloud: cloud,
                      action: () => _buy(context, cloud, AppTier.xl),
                      request: () => _requestAccess(context, cloud, AppTier.xl),
                    ),
                    const Divider(height: 28),
                    _TierRow(
                      tier: AppTier.xxl,
                      title: cloud.paymentsLive
                          ? 'XXL · ₹${cloud.priceMinor(AppTier.xxl) ~/ 100} once'
                          : 'XXL',
                      description:
                          'Unlimited saves and collections · import compatible custom models\nIncludes future advanced local features as they become available.',
                      cloud: cloud,
                      action: () => _buy(context, cloud, AppTier.xxl),
                      request: () =>
                          _requestAccess(context, cloud, AppTier.xxl),
                    ),
                    const SizedBox(height: 8),
                    if (signedIn &&
                        const bool.fromEnvironment('LINQO_POLAR_SANDBOX'))
                      PolarSandboxCard(
                        key: ValueKey(cloud.identity.uid),
                        cloud: cloud,
                      ),
                    const Text(
                      'Built-in English extraction and password-protected backups stay free. Compatible custom-model imports are reserved for XXL; already installed models are preserved. Donations support development and are separate from access requests.',
                    ),
                    const SizedBox(height: 8),
                    if (signedIn && cloud.accountCode.isNotEmpty) ...[
                      const Text('Your Linqo account code'),
                      SelectableText(cloud.accountCode),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: cloud.accountCode),
                          );
                          if (context.mounted) {
                            message(
                              context,
                              'Account code copied. Email it privately with your payment reference.',
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copy account code'),
                      ),
                    ] else if (signedIn)
                      TextButton(
                        onPressed: disabled || !CloudConfig.backendReady
                            ? null
                            : () => _act(
                                context,
                                () => cloud.run(cloud.restorePurchase),
                              ),
                        child: const Text('Get account code'),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _act(context, () async {
                            if (!await launchUrl(
                              Uri.parse(
                                'mailto:aryandurgude123@gmail.com?subject=Linqo%20support',
                              ),
                            )) {
                              throw StateError(
                                'Could not open email. Contact aryandurgude123@gmail.com.',
                              );
                            }
                          }),
                          icon: const Icon(Icons.mail_outline_rounded),
                          label: const Text('Email the developer'),
                        ),
                        for (final (url, label, icon) in const [
                          (
                            'https://buymeacoffee.com/notal2',
                            'Buy me a coffee',
                            Icons.coffee_outlined,
                          ),
                          (
                            'https://buymeatea.online/notal2',
                            'Buy me a tea · India',
                            Icons.emoji_food_beverage_outlined,
                          ),
                        ])
                          TextButton.icon(
                            onPressed: () => _act(context, () async {
                              if (!await launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.externalApplication,
                              )) {
                                throw StateError(
                                  'Could not open the support page. Try $url in your browser.',
                                );
                              }
                            }),
                            icon: Icon(icon),
                            label: Text(label),
                          ),
                      ],
                    ),
                    Text(
                      checkoutAvailable
                          ? 'Future customization and enhanced model options are not available yet. Read the purchase and refund policy before paying.'
                          : 'Future customization and enhanced model options are not available yet. No payment is accepted through this prebuild. Existing purchases retain their refund rights; see the purchase and refund policy.',
                    ),
                    TextButton(
                      onPressed: () => _act(context, () async {
                        if (!await launchUrl(
                          Uri.parse(
                            'https://linqo-app-notal2.web.app/purchases',
                          ),
                          mode: LaunchMode.externalApplication,
                        )) {
                          throw StateError(
                            'Could not open the purchase policy.',
                          );
                        }
                      }),
                      child: const Text('Purchases & refund policy'),
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
                      'Your backups, your choice',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a password-protected backup with Export saves in Settings, then choose Drive in the Files picker. Use Import saves to open a backup from Drive. Earlier Linqo app-data snapshots can still be restored below; no new automatic Drive uploads are made.',
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Connect earlier Drive backups'),
                      subtitle: const Text(
                        'Read existing Linqo snapshots from this Google account',
                      ),
                      value: cloud.driveEnabled,
                      onChanged: disabled || !signedIn
                          ? null
                          : (value) => _act(context, () async {
                              if (value &&
                                  !await _confirm(
                                    context,
                                    'Connect your earlier backups?',
                                    'This requests access to earlier Linqo app-data snapshots in ${cloud.identity.email}. It does not upload your library. New encrypted backups use the Files picker.',
                                    'Connect backups',
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
                        CloudConfig.contributionsEnabled
                            ? 'Off by default · at most two daily · Wi-Fi and idle only'
                            : 'Paused in this preview · no source samples are uploaded',
                      ),
                      value: cloud.contributions,
                      onChanged:
                          disabled ||
                              !signedIn ||
                              !CloudConfig.backendReady ||
                              !CloudConfig.contributionsEnabled
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
                      'Encrypted export/import works through Files, including your Drive provider, without signing into Linqo. Keep your backup password and important originals.',
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
                    if (signedIn) ...[
                      const Divider(height: 32),
                      TextButton.icon(
                        onPressed: disabled
                            ? null
                            : () => _act(context, () async {
                                if (!await _confirm(
                                  context,
                                  'Sign out of Linqo?',
                                  'Your local saves, settings, files and installed model stay on this device. Account access is removed until you sign in again with the same Google account.',
                                  'Sign out',
                                )) {
                                  return;
                                }
                                await cloud.signOut();
                              }),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sign out · keep local saves'),
                      ),
                    ],
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

class _UsageMeter extends StatelessWidget {
  const _UsageMeter({
    required this.label,
    required this.count,
    required this.limit,
  });
  final String label;
  final int count;
  final int? limit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        limit == null ? '$count $label · unlimited' : '$count of $limit $label',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (limit != null) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (count / limit!).clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(8),
          semanticsLabel: '$label used: $count of $limit',
        ),
        if (count > limit!) ...[
          const SizedBox(height: 6),
          Text(
            'Above the limit · existing content is preserved',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ],
  );
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.title,
    required this.description,
    required this.cloud,
    required this.action,
    required this.request,
  });
  final AppTier tier;
  final String title, description;
  final CloudServices cloud;
  final VoidCallback action, request;
  bool get checkoutAvailable =>
      CloudConfig.checkoutEnabled &&
      cloud.paymentsLive &&
      cloud.identity.uid != null;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(description),
      const SizedBox(height: 8),
      if (cloud.tier.index >= tier.index)
        Chip(
          avatar: const Icon(Icons.check_rounded, size: 18),
          label: Text(cloud.tier == tier ? 'Your tier' : 'Included'),
        )
      else
        OutlinedButton(
          onPressed: cloud.busy
              ? null
              : checkoutAvailable
              ? action
              : request,
          child: Text(
            checkoutAvailable
                ? 'Choose ${tier.name.toUpperCase()}'
                : 'Request ${tier.name.toUpperCase()} access',
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
