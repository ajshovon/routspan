import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/data/router_profile.dart';
import 'package:routspan/providers/profiles.dart';

/// Add a new saved router, or edit an existing one.
class RouterFormScreen extends ConsumerStatefulWidget {
  const RouterFormScreen({super.key, this.existing});

  /// Null = add mode; non-null = edit mode.
  final RouterProfile? existing;

  @override
  ConsumerState<RouterFormScreen> createState() => _RouterFormScreenState();
}

class _RouterFormScreenState extends ConsumerState<RouterFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtl;
  late final TextEditingController _hostCtl;
  final _passCtl = TextEditingController();

  late bool _reqproc;
  late bool _makeDefault;
  bool _obscure = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtl = TextEditingController(text: e?.name ?? '');
    _hostCtl = TextEditingController(text: e?.host ?? '192.168.8.1');
    _reqproc = e?.reqproc ?? true;
    // In edit mode the current default state is resolved in build via provider.
    _makeDefault = false;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _hostCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ctrl = ref.read(profilesControllerProvider.notifier);
    final name = _nameCtl.text.trim();
    final host = _hostCtl.text.trim();
    final pass = _passCtl.text;
    try {
      if (_isEdit) {
        await ctrl.edit(
          widget.existing!.copyWith(name: name, host: host, reqproc: _reqproc),
          password: pass.isEmpty ? null : pass,
          makeDefault: _makeDefault,
        );
      } else {
        await ctrl.add(
          name: name,
          host: host,
          reqproc: _reqproc,
          password: pass.isEmpty ? null : pass,
          makeDefault: _makeDefault,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentDefault = _isEdit &&
        ref.watch(profilesControllerProvider
                .select((s) => s.valueOrNull?.defaultId)) ==
            widget.existing!.id;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit router' : 'Add router')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameCtl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Home OLAX',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hostCtl,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Router IP',
                prefixIcon: Icon(Icons.lan),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter the router IP'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passCtl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Admin password',
                helperText:
                    _isEdit ? 'Leave blank to keep the saved password' : null,
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Newer firmware (reqproc)'),
              subtitle: const Text(
                  'On for OLAX M100. Off for legacy goform devices.'),
              value: _reqproc,
              onChanged: (v) => setState(() => _reqproc = v),
            ),
            if (isCurrentDefault)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.star, color: Colors.amber),
                title: Text('This is your default router'),
                subtitle:
                    Text('The app connects to it automatically on launch.'),
              )
            else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set as default'),
                subtitle: const Text('Auto-connect to this router on launch.'),
                value: _makeDefault,
                onChanged: (v) => setState(() => _makeDefault = v),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isEdit ? 'Save' : 'Add router'),
            ),
          ],
        ),
      ),
    );
  }
}
