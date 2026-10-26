import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/db.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'data/models.dart';
import 'features/admin/admin_shell.dart';
import 'features/auth/login_portal.dart';
import 'features/client/client_shell.dart';
import 'features/company/company_shell.dart';
import 'features/worker/worker_shell.dart';
import 'widgets/common.dart';

class KoraVubaApp extends StatefulWidget {
  const KoraVubaApp({super.key});

  @override
  State<KoraVubaApp> createState() => _KoraVubaAppState();
}

class _KoraVubaAppState extends State<KoraVubaApp> {
  Session? _session;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await AppDb.open();
      final s = Session(prefs);
      await s.restore();
      if (mounted) setState(() => _session = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: _Splash(error: _error, onRetry: () {
          setState(() => _error = null);
          _boot();
        }),
      );
    }
    return ChangeNotifierProvider<Session>.value(
      value: s,
      child: Consumer<Session>(
        builder: (context, session, _) => MaterialApp(
          title: 'KoraVuba',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: session.themeMode,
          home: const RootGate(),
        ),
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (!s.signedIn) return const LoginPortal();
    final key = ValueKey('${s.role}-${s.user!.id}');
    return switch (s.role!) {
      Role.client => ClientShell(key: key),
      Role.worker => WorkerShell(key: key),
      Role.company => CompanyShell(key: key),
      Role.admin => AdminShell(key: key),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const KvLogo(size: 96),
            const SizedBox(height: 18),
            const Wordmark(size: 30),
            const SizedBox(height: 8),
            const Text('Company-verified on-demand services', style: TextStyle(color: Kv.s400)),
            const SizedBox(height: 28),
            if (error == null)
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6))
            else ...[
              Text('Could not open the database:\n$error', textAlign: TextAlign.center, style: const TextStyle(color: Kv.red)),
              const SizedBox(height: 16),
              KvButton(label: 'Try again', expand: false, onPressed: onRetry),
            ],
          ]),
        ),
      ),
    );
  }
}
