import 'package:flutter/material.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({required this.profile, super.key});

  final LocalProfile profile;

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.profile.displayName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Local profile'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                key: const ValueKey<String>('display-name-input'),
                controller: _controller,
                autofocus: true,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  helperText: 'Shown to nearby MeshTalk peers',
                ),
                validator: (value) {
                  final normalized = _normalize(value ?? '');
                  if (normalized.length < 2) {
                    return 'Enter at least 2 characters.';
                  }
                  if (normalized.length > 24) {
                    return 'Use no more than 24 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Text('Device ID'),
              const SizedBox(height: 4),
              SelectableText(widget.profile.deviceId),
              const SizedBox(height: 12),
              const Text(
                'This identity and your message history stay on this device.',
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('save-profile-button'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_normalize(_controller.text));
  }

  String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}
