import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/data/router_profile.dart';
import 'package:routspan/features/routers/router_form_screen.dart';
import 'package:routspan/providers/profiles.dart';
import 'package:routspan/providers/session.dart';

/// Startup hub: the list of saved routers. Tap one to connect (using its stored
/// password), star one as default (auto-connect on launch), add/edit/remove.
class RouterListScreen extends ConsumerStatefulWidget {
  const RouterListScreen({super.key});

  @override
  ConsumerState<RouterListScreen> createState() => _RouterListScreenState();
}

class _RouterListScreenState extends ConsumerState<RouterListScreen> {
  @override
  void initState() {
    super.initState();
    // Covers the case where profiles are already loaded on first mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(profilesControllerProvider).value;
      if (s != null) _maybeAutoConnect(s.defaultProfile);
    });
  }

  Future<void> _maybeAutoConnect(RouterProfile? def) async {
    if (def == null || !mounted) return;
    if (ref.read(autoConnectAttemptedProvider)) return;
    if (ref.read(sessionControllerProvider).status != ConnStatus.disconnected) {
      return;
    }
    ref.read(autoConnectAttemptedProvider.notifier).state = true;
    final pw =
        await ref.read(profilesControllerProvider.notifier).passwordFor(def.id);
    if (pw == null || pw.isEmpty || !mounted) return;
    await ref.read(sessionControllerProvider.notifier).connect(
          host: def.host,
          password: pw,
          reqprocDialect: def.reqproc,
          profileId: def.id,
          name: def.name,
        );
  }

  Future<void> _connect(RouterProfile p) async {
    final ctrl = ref.read(profilesControllerProvider.notifier);
    var pw = await ctrl.passwordFor(p.id);
    if ((pw == null || pw.isEmpty) && mounted) {
      final entered = await _promptPassword(p);
      if (entered == null) return;
      pw = entered.$1;
      if (entered.$2) await ctrl.savePassword(p.id, pw);
    }
    if (pw == null || pw.isEmpty || !mounted) return;
    await ref.read(sessionControllerProvider.notifier).connect(
          host: p.host,
          password: pw,
          reqprocDialect: p.reqproc,
          profileId: p.id,
          name: p.name,
        );
  }

  /// Returns (password, savePassword) or null if cancelled.
  Future<(String, bool)?> _promptPassword(RouterProfile p) async {
    final ctl = TextEditingController();
    var save = true;
    var obscure = true;
    return showDialog<(String, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Password for ${p.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctl,
                autofocus: true,
                obscureText: obscure,
                onSubmitted: (v) => Navigator.pop(ctx, (v, save)),
                decoration: InputDecoration(
                  labelText: 'Admin password',
                  suffixIcon: IconButton(
                    icon:
                        Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setLocal(() => obscure = !obscure),
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Save password'),
                value: save,
                onChanged: (v) => setLocal(() => save = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, (ctl.text, save)),
                child: const Text('Connect')),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(RouterProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: const Text('This forgets the router and its saved password.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(profilesControllerProvider.notifier).remove(p.id);
    }
  }

  void _openForm({RouterProfile? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouterFormScreen(existing: existing),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Auto-connect once profiles finish loading.
    ref.listen<AsyncValue<ProfilesState>>(profilesControllerProvider,
        (prev, next) {
      final s = next.value;
      if (s != null) _maybeAutoConnect(s.defaultProfile);
    });
    // Surface connection failures.
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      if (next.status == ConnStatus.error && next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect: ${next.error}')),
        );
      }
    });

    final session = ref.watch(sessionControllerProvider);
    if (session.status == ConnStatus.connecting) {
      return _ConnectingView(label: session.label);
    }

    final profilesAsync = ref.watch(profilesControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Routers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add router'),
      ),
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          if (s.profiles.isEmpty) return _empty(context);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final p in s.profiles)
                _RouterTile(
                  profile: p,
                  isDefault: p.id == s.defaultId,
                  onTap: () => _connect(p),
                  onSetDefault: () => ref
                      .read(profilesControllerProvider.notifier)
                      .setDefault(p.id),
                  onEdit: () => _openForm(existing: p),
                  onForget: () => ref
                      .read(profilesControllerProvider.notifier)
                      .forgetPassword(p.id),
                  onDelete: () => _delete(p),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              dark
                  ? 'assets/logo/logo_full_dark.png'
                  : 'assets/logo/logo_full_light.png',
              height: 48,
            ),
            const SizedBox(height: 24),
            Text('No routers yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Add your OLAX M100 (or another MiFi) to get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add router'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouterTile extends StatelessWidget {
  const _RouterTile({
    required this.profile,
    required this.isDefault,
    required this.onTap,
    required this.onSetDefault,
    required this.onEdit,
    required this.onForget,
    required this.onDelete,
  });

  final RouterProfile profile;
  final bool isDefault;
  final VoidCallback onTap;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onForget;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.router,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(profile.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (isDefault) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star, size: 16, color: Colors.amber),
            ],
          ],
        ),
        subtitle: Text(profile.host),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'default':
                onSetDefault();
              case 'edit':
                onEdit();
              case 'forget':
                onForget();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => [
            if (!isDefault)
              const PopupMenuItem(
                value: 'default',
                child: ListTile(
                    leading: Icon(Icons.star_outline),
                    title: Text('Set as default')),
              ),
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                  leading: Icon(Icons.edit_outlined), title: Text('Edit')),
            ),
            const PopupMenuItem(
              value: 'forget',
              child: ListTile(
                  leading: Icon(Icons.password),
                  title: Text('Forget password')),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  leading: Icon(Icons.delete_outline), title: Text('Remove')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Connecting to $label…',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
