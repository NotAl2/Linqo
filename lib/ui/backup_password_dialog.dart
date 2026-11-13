import 'package:flutter/material.dart';

Future<String?> backupPassword(
  BuildContext context, {
  required bool creating,
}) => showDialog<String>(
  context: context,
  builder: (_) => _BackupPasswordDialog(creating: creating),
);

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.creating});
  final bool creating;
  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final password = TextEditingController(), confirm = TextEditingController();
  final form = GlobalKey<FormState>();
  bool visible = false;
  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.creating ? 'Protect your backup' : 'Unlock your backup'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.creating
                  ? 'Keep this password somewhere safe. You need it to restore, and Linqo cannot recover it. It is not sent to Linqo or Google.'
                  : 'Enter the password used when this backup was created.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: password,
              obscureText: !visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Backup password',
                suffixIcon: IconButton(
                  tooltip: visible ? 'Hide password' : 'Show password',
                  onPressed: () => setState(() => visible = !visible),
                  icon: Icon(
                    visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (s) => s == null || s.isEmpty
                  ? 'Enter your backup password.'
                  : widget.creating && s.length < 12
                  ? 'Use at least 12 characters.'
                  : s.length > 256
                  ? 'Use at most 256 characters.'
                  : null,
            ),
            if (widget.creating) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: confirm,
                obscureText: !visible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (s) =>
                    s != password.text ? 'The passwords do not match.' : null,
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, password.text);
          }
        },
        child: Text(widget.creating ? 'Encrypt backup' : 'Unlock backup'),
      ),
    ],
  );
}
