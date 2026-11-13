import 'package:flutter/material.dart';
import '../services/cloud_services.dart';
import '../services/cloud_api.dart';
import '../services/checkout_purchase.dart';
import '../services/cloud_config.dart';
import '../services/tiers.dart';

class PolarSandboxCard extends StatefulWidget {
  const PolarSandboxCard({super.key, required this.cloud});
  final CloudServices cloud;
  @override
  State<PolarSandboxCard> createState() => _PolarSandboxCardState();
}

class _PolarSandboxCardState extends State<PolarSandboxCard> {
  bool busy = false;
  String status = 'Test payments only. No real money or paid unlock.';
  Future<void> act(Future<String> Function(String owner) action) async {
    final owner = widget.cloud.identity.uid;
    if (owner == null || busy) return;
    setState(() => busy = true);
    try {
      final result = await action(owner);
      if (mounted && widget.cloud.identity.uid == owner) {
        setState(() => status = result);
      }
    } catch (error) {
      if (mounted && widget.cloud.identity.uid == owner) {
        setState(
          () => status = error is CloudRequestError
              ? 'Sandbox check failed: ${error.code}'
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> buy(String owner, AppTier tier) async {
    final value = await widget.cloud.api.call(
      '/polar/sandbox/checkout',
      method: 'POST',
      body: {'tier': tier.name, 'request_id': newPurchaseRequestId()},
    );
    if (widget.cloud.identity.uid != owner) {
      throw StateError('Account changed. Start again.');
    }
    final purchase = CheckoutPurchase.parse(
      value,
      tier,
      accountId: owner,
      checkoutOrigin: CloudConfig.backend,
      expectedProvider: 'polar',
    );
    await widget.cloud.openPurchase(purchase);
    return 'Checkout opened. Use Polar sandbox test details, then return here and restore the test purchase.';
  }

  Future<String> liveAcceptance(String owner, AppTier tier) async {
    final value = await widget.cloud.api.call(
      '/polar/live/checkout',
      method: 'POST',
      body: {'tier': tier.name, 'request_id': newPurchaseRequestId()},
    );
    if (widget.cloud.identity.uid != owner) {
      throw StateError('Account changed. Start again.');
    }
    final purchase = CheckoutPurchase.parse(
      value,
      tier,
      accountId: owner,
      checkoutOrigin: CloudConfig.backend,
      expectedProvider: 'polar',
      expectedAmountMinor: 0,
      privateFreeAcceptance: true,
    );
    await widget.cloud.openPurchase(purchase);
    return 'Private live checkout opened. Confirm the final total is zero. Return here to restore.';
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Polar sandbox · QA only',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(status)),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => act((_) async {
                        final value = await widget.cloud.api.call(
                          '/polar/sandbox/catalog',
                        );
                        if (value['sandbox'] != true) {
                          throw StateError('Unexpected checkout environment.');
                        }
                        return 'Sandbox token and both INR product prices verified.';
                      }),
                child: const Text('Check Polar setup'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => act((owner) => buy(owner, AppTier.xl)),
                child: const Text('Test XL · ₹449'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => act((owner) => buy(owner, AppTier.xxl)),
                child: const Text('Test XXL · ₹649'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => act((_) async {
                        final value = await widget.cloud.api.call(
                          '/polar/sandbox/restore',
                        );
                        final tier = value['sandbox_tier'];
                        if (value['sandbox'] != true ||
                            !const ['free', 'xl', 'xxl'].contains(tier)) {
                          throw StateError('Invalid test result.');
                        }
                        return 'Sandbox purchase: ${(tier as String).toUpperCase()}. Real paid access is unchanged.';
                      }),
                child: const Text('Restore test purchase'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Private live acceptance · zero total only'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => act((owner) => liveAcceptance(owner, AppTier.xl)),
                child: const Text('Live XL · ₹0'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => act((owner) => liveAcceptance(owner, AppTier.xxl)),
                child: const Text('Live XXL · ₹0'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => act((_) async {
                        await widget.cloud.restorePurchase();
                        return 'Live account tier: ${widget.cloud.tier.name.toUpperCase()}';
                      }),
                child: const Text('Restore live purchase'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
