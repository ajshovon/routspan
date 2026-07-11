import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/core/errors.dart';
import 'package:routspan/data/router_repository.dart';
import 'package:routspan/features/common/async_view.dart';
import 'package:routspan/features/sms/sms_format.dart';
import 'package:routspan/providers/features.dart';
import 'package:routspan/providers/session.dart';

/// A single SMS conversation rendered as a chat: received messages on the left,
/// sent on the right, with a composer to reply.
class SmsThreadScreen extends ConsumerStatefulWidget {
  const SmsThreadScreen({super.key, required this.number});
  final String number;

  @override
  ConsumerState<SmsThreadScreen> createState() => _SmsThreadScreenState();
}

class _SmsThreadScreenState extends ConsumerState<SmsThreadScreen> {
  final _composeCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  bool _sending = false;
  bool _markedRead = false;

  @override
  void dispose() {
    _composeCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _markReadOnce(SmsConversation convo) {
    if (_markedRead || !convo.hasUnread) return;
    _markedRead = true;
    ref.read(repositoryProvider).markSmsRead(convo.unreadIds).then(
          (_) => ref.invalidate(smsListProvider),
          onError: (_) {},
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtl.hasClients) {
        _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _composeCtl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).sendSms(widget.number, text);
      _composeCtl.clear();
      ref.invalidate(smsListProvider);
      ref.invalidate(smsCapacityProvider);
      _scrollToBottom();
    } on RouterException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteConversation(SmsConversation convo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
            'Delete all ${convo.messages.length} message(s) with ${widget.number}? This cannot be undone.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(repositoryProvider).deleteSms(convo.allIds);
      ref.invalidate(smsListProvider);
      ref.invalidate(smsCapacityProvider);
      navigator.pop();
    } on RouterException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _messageActions(SmsMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.content));
      messenger.showSnackBar(const SnackBar(content: Text('Copied')));
    } else if (action == 'delete' && mounted) {
      await runAction(
        context,
        ref,
        () => ref.read(repositoryProvider).deleteSms([m.id]),
        success: 'Message deleted',
        refresh: smsListProvider,
      );
      ref.invalidate(smsCapacityProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final convoAsync = ref.watch(smsConversationProvider(widget.number));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ContactAvatar(number: widget.number, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.number.isEmpty ? '(unknown)' : widget.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          convoAsync.maybeWhen(
            data: (convo) => convo == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Delete conversation',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteConversation(convo),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AsyncView<SmsConversation?>(
              value: convoAsync,
              onRetry: () => ref.invalidate(smsListProvider),
              builder: (convo) {
                if (convo == null || convo.messages.isEmpty) {
                  return _emptyThread(context);
                }
                _markReadOnce(convo);
                _scrollToBottom();
                return _messageList(convo);
              },
            ),
          ),
          _composer(context),
        ],
      ),
    );
  }

  Widget _emptyThread(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.chat_bubble_outline,
            size: 48, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Center(
          child: Text('Send a message to ${widget.number}',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _messageList(SmsConversation convo) {
    // Build a flat item list with day-separator headers between days.
    final items = <Widget>[];
    DateTime? lastDay;
    for (final m in convo.messages) {
      final ts = m.timestamp;
      if (ts != null) {
        final day = DateTime(ts.year, ts.month, ts.day);
        if (lastDay == null || day != lastDay) {
          items.add(_DayHeader(label: smsDayHeader(ts)));
          lastDay = day;
        }
      }
      items.add(_MessageBubble(
        message: m,
        onLongPress: () => _messageActions(m),
      ));
    }
    return ListView(
      controller: _scrollCtl,
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: items,
    );
  }

  Widget _composer(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _composeCtl,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: 'Text message',
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onLongPress});
  final SmsMessage message;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sent = message.isSent;
    final draft = message.isDraft;
    final align = sent ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = draft
        ? theme.colorScheme.surfaceContainerHighest
        : sent
            ? theme.colorScheme.primary
            : theme.colorScheme.secondaryContainer;
    final textColor = draft
        ? theme.colorScheme.onSurface
        : sent
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSecondaryContainer;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(sent ? 16 : 4),
      bottomRight: Radius.circular(sent ? 4 : 16),
    );

    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration:
                  BoxDecoration(color: bubbleColor, borderRadius: radius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.content,
                    style: TextStyle(color: textColor, height: 1.3),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (draft) ...[
                        Text('Draft',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: textColor.withValues(alpha: 0.7),
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        smsFullTime(message.timestamp).split('· ').last,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: textColor.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
