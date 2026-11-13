import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tiers.dart';
import 'policy_screen.dart';

class CheckoutDialog extends StatefulWidget {
  const CheckoutDialog({
    super.key,
    required this.tier,
    required this.accountLabel,
    required this.sandbox,
    this.amountMinor,
    this.provider = 'cashfree',
  });
  final AppTier tier;
  final String accountLabel;
  final bool sandbox;
  final int? amountMinor;
  final String provider;
  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  final phone = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final xxl = widget.tier == AppTier.xxl;
    final polar = widget.provider == 'polar';
    return AlertDialog(
      title: Text(
        'Linqo ${xxl ? 'XXL' : 'XL'} · ₹${(widget.amountMinor ?? (xxl ? 64900 : 44900)) ~/ 100} once',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                xxl
                    ? 'Unlimited saves and collections, plus compatible custom-model imports.'
                    : '500 saves and 30 collections.',
              ),
              const SizedBox(height: 16),
              if (widget.sandbox) ...[
                Text(
                  'Sandbox test · no paid unlock',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use ${polar ? 'Polar' : 'Cashfree'} test details only. Sandbox payments do not charge real money or unlock a tier.',
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'This purchase belongs to ${widget.accountLabel}. Use the same Google account to restore it later.',
              ),
              const SizedBox(height: 16),
              if (!polar)
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  maxLength: 16,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[+0-9]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone number with country code',
                    hintText: '+91…',
                    counterText: '',
                  ),
                  validator: (value) =>
                      RegExp(
                        r'^\+[1-9][0-9]{7,14}$',
                      ).hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Include + and your country code.',
                ),
              const SizedBox(height: 12),
              if (!polar)
                const Text(
                  'Cashfree needs a phone number to create checkout. Linqo forwards it securely and does not save it in your library or payment ledger.',
                ),
              const SizedBox(height: 12),
              if (polar)
                const Text(
                  'Polar is the Merchant of Record and collects required billing details in its secure checkout. Linqo does not ask for your phone number or card details.',
                ),
              const SizedBox(height: 12),
              const Text(
                'One-time purchase, no subscription. XL to XXL costs the full XXL price in addition to XL. Request a full refund within 15 calendar days; mandatory rights remain protected.',
              ),
              Wrap(
                children: [
                  for (final (label, asset) in const [
                    ('Purchase & refund policy', 'policies/PURCHASES.md'),
                    ('Terms', 'policies/TERMS.md'),
                    ('Privacy', 'policies/PRIVACY.md'),
                  ])
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PolicyScreen(title: label, asset: asset),
                        ),
                      ),
                      child: Text(label),
                    ),
                ],
              ),
              const Text(
                'Continuing accepts Linqo’s terms and purchase policy. Polar’s buyer terms also apply at checkout.',
              ),
              const Text(
                'Payment opens in your browser. After paying, return to Linqo and choose Restore purchase. Donations do not unlock a tier.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, phone.text.trim());
            }
          },
          child: Text('Continue to ${polar ? 'Polar' : 'Cashfree'}'),
        ),
      ],
    );
  }
}
