import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/features/home/home_shell.dart';
import 'package:routspan/features/routers/router_list_screen.dart';
import 'package:routspan/providers/session.dart';

class RouterApp extends ConsumerWidget {
  const RouterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        ref.watch(sessionControllerProvider.select((s) => s.isConnected));

    return MaterialApp(
      title: 'Routspan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: connected ? const HomeShell() : const RouterListScreen(),
    );
  }
}
