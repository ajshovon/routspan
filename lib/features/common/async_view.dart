import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/core/errors.dart';

/// Renders an [AsyncValue] with consistent loading / error / data states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(_message(e), textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                    onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _message(Object e) => e is RouterException ? e.message : e.toString();

/// Runs a write [action] with standard feedback: a snackbar on success/failure
/// and an optional provider invalidation to refresh the UI afterwards.
Future<void> runAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  required String success,
  ProviderOrFamily? refresh,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (refresh != null) ref.invalidate(refresh);
    messenger.showSnackBar(SnackBar(content: Text(success)));
  } on RouterException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
