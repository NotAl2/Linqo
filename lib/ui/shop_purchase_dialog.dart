import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shop_purchase.dart';
import '../services/tiers.dart';

class ShopPurchaseDialog extends StatefulWidget {
  const ShopPurchaseDialog({
    super.key,
    required this.purchase,
    required this.accountLabel,
  });
  final ShopPurchase purchase;
  final String accountLabel;
  @override
  State<ShopPurchaseDialog> createState() => _ShopPurchaseDialogState();
}

class _ShopPurchaseDialogState extends State<ShopPurchaseDialog> {
  bool copied = false;
  @override
  Widget build(BuildContext context) {
    final xxl = widget.purchase.tier == AppTier.xxl;
    return AlertDialog(
      title: Text('Linqo ${xxl ? 'XXL' : 'XL'} · US\$${xxl ? 7 : 5} once'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              xxl
                  ? 'Unlimited saves and collections, plus compatible custom-model imports.'
                  : '250 saves and 25 collections.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Copy your code, then paste it into “Linqo purchase code” at Buy Me a Coffee checkout.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              widget.purchase.code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              'This purchase will belong to ${widget.accountLabel}. Sign in with the same Google account to restore it later.',
            ),
            const SizedBox(height: 12),
            const Text(
              'After paying, return here and choose Restore purchase. Donations do not unlock a tier.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.purchase.code));
            if (mounted) setState(() => copied = true);
          },
          icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded),
          label: Text(copied ? 'Code copied' : 'Copy code'),
        ),
        FilledButton(
          onPressed: copied ? () => Navigator.pop(context, true) : null,
          child: const Text('Open Shop'),
        ),
      ],
    );
  }
}
