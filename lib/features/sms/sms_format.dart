import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Short timestamp for the conversation list: time if today, weekday if this
/// week, otherwise a date.
String smsRelativeTime(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return DateFormat('HH:mm').format(d);
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEE').format(d);
  if (d.year == now.year) return DateFormat('MMM d').format(d);
  return DateFormat('MMM d, y').format(d);
}

/// Full timestamp used inside a thread ("Jul 11, 2026 · 18:01").
String smsFullTime(DateTime? d) =>
    d == null ? '' : DateFormat('MMM d, y · HH:mm').format(d);

/// Header shown between messages sent on different days.
String smsDayHeader(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (d.year == now.year) return DateFormat('EEEE, MMM d').format(d);
  return DateFormat('MMM d, y').format(d);
}

/// A phone number vs. an alphanumeric sender id like "Robi".
bool smsIsNumeric(String s) =>
    s.isNotEmpty && RegExp(r'^[+\d][\d\s\-()]*$').hasMatch(s);

/// Deterministic accent colour for a contact so avatars stay stable per number.
Color smsAvatarColor(String key) {
  const palette = [
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFF8E24AA),
    Color(0xFFF4511E),
    Color(0xFF00897B),
    Color(0xFF3949AB),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
  ];
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Circle avatar showing the contact's initial (or a person icon for a bare
/// number).
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({super.key, required this.number, this.radius = 22});

  final String number;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = smsAvatarColor(number);
    final numeric = smsIsNumeric(number) || number.isEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundColor: Colors.white,
      child: numeric
          ? Icon(Icons.person, size: radius * 1.05)
          : Text(
              number.characters.first.toUpperCase(),
              style: TextStyle(
                  fontSize: radius * 0.8, fontWeight: FontWeight.w600),
            ),
    );
  }
}
