import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/data/router_repository.dart';
import 'package:routspan/features/common/async_view.dart';
import 'package:routspan/features/sms/sms_format.dart';
import 'package:routspan/features/sms/sms_thread_screen.dart';
import 'package:routspan/providers/features.dart';

/// M3 — SMS, revamped as an Android-Messages-style conversation list. Messages
/// are grouped by number; tapping a row opens the [SmsThreadScreen].
class SmsScreen extends ConsumerWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(smsConversationsProvider);
    final capacity = ref.watch(smsCapacityProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newMessage(context, ref),
        icon: const Icon(Icons.edit),
        label: const Text('New'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(smsListProvider);
          ref.invalidate(smsCapacityProvider);
        },
        child: AsyncView<List<SmsConversation>>(
          value: conversations,
          onRetry: () => ref.invalidate(smsListProvider),
          builder: (convos) {
            if (convos.isEmpty) {
              return const _EmptyList(text: 'No messages');
            }
            return ListView.separated(
              itemCount: convos.length + 1,
              separatorBuilder: (_, i) => i == 0
                  ? const SizedBox.shrink()
                  : const Divider(height: 1, indent: 76),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _CapacityHeader(capacity: capacity.value);
                }
                return _ConversationTile(
                  conversation: convos[i - 1],
                  onTap: () => _openThread(context, convos[i - 1].number),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _openThread(BuildContext context, String number) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SmsThreadScreen(number: number),
      ),
    );
  }

  Future<void> _newMessage(BuildContext context, WidgetRef ref) async {
    final numberCtl = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New message'),
        content: TextField(
          controller: numberCtl,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'To (number)',
            prefixIcon: Icon(Icons.person_add_alt),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, numberCtl.text.trim()),
              child: const Text('Next')),
        ],
      ),
    );
    if (number == null || number.isEmpty || !context.mounted) return;
    _openThread(context, number);
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});
  final SmsConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = conversation.latest;
    final unread = conversation.hasUnread;
    final preview =
        (latest.isSent ? 'You: ' : '') + latest.content.replaceAll('\n', ' ');
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: ContactAvatar(number: conversation.number),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.number.isEmpty ? '(unknown)' : conversation.number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: unread ? FontWeight.bold : FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            smsRelativeTime(latest.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: unread ? theme.colorScheme.primary : null,
              fontWeight: unread ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unread ? FontWeight.w600 : null,
                color: unread ? theme.colorScheme.onSurface : null,
              ),
            ),
          ),
          if (unread) ...[
            const SizedBox(width: 8),
            _UnreadBadge(count: conversation.unreadCount),
          ] else if (conversation.messages.length > 1) ...[
            const SizedBox(width: 8),
            Text('${conversation.messages.length}',
                style: theme.textTheme.bodySmall),
          ],
        ],
      ),
      isThreeLine: true,
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CapacityHeader extends StatelessWidget {
  const _CapacityHeader({required this.capacity});
  final SmsCapacity? capacity;

  @override
  Widget build(BuildContext context) {
    if (capacity == null || capacity!.deviceTotal == 0) {
      return const SizedBox.shrink();
    }
    final c = capacity!;
    final parts = [
      'Device ${c.deviceUsed}/${c.deviceTotal}',
      if (c.simTotal > 0) 'SIM ${c.simUsed}/${c.simTotal}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Icon(Icons.sim_card_outlined,
              size: 16, color: Theme.of(context).hintColor),
          const SizedBox(width: 6),
          Text(parts.join('  ·  '),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.forum_outlined,
            size: 56, color: Theme.of(context).disabledColor),
        const SizedBox(height: 8),
        Center(child: Text(text)),
      ],
    );
  }
}
