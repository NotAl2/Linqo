import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tiers.dart';

class CheckoutDialog extends StatefulWidget {
  const CheckoutDialog({
    super.key,
    required this.tier,
    required this.accountLabel,
    required this.sandbox,
  });
  final AppTier tier;
  final String accountLabel;
  final bool sandbox;
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
    return AlertDialog(
      title: Text('Linqo ${xxl ? 'XXL' : 'XL'} · ₹${xxl ? 649 : 449} once'),
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
                    : '250 saves and 25 collections.',
              ),
              const SizedBox(height: 16),
              if (widget.sandbox) ...[
                Text(
                  'Sandbox test · no paid unlock',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use Cashfree test details only. Sandbox payments do not charge real money or unlock a tier.',
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'This purchase belongs to ${widget.accountLabel}. Use the same Google account to restore it later.',
              ),
              const SizedBox(height: 16),
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
              const Text(
                'Cashfree needs a phone number to create checkout. Linqo forwards it securely and does not save it in your library or payment ledger.',
              ),
              const SizedBox(height: 12),
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
            if (form.currentState!.validate())
              Navigator.pop(context, phone.text.trim());
          },
          child: const Text('Continue to Cashfree'),
        ),
      ],
    );
  }
}
