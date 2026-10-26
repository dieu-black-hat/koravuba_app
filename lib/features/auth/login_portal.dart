import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/theme.dart';
import '../../data/auth_repo.dart';
import '../../data/catalog_repo.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';

Color roleColor(Role r) => switch (r) {
      Role.client => Kv.emerald,
      Role.worker => Kv.amber,
      Role.company => Kv.blue,
      Role.admin => Kv.purple,
    };

/// LoginPortal from the design: Client / Worker / Company tabs, Sign In /
/// Create Account. Long-press the logo for KoraVuba HQ.
class LoginPortal extends StatefulWidget {
  const LoginPortal({super.key});

  @override
  State<LoginPortal> createState() => _LoginPortalState();
}

class _LoginPortalState extends State<LoginPortal> {
  late Role _role;
  bool _signUp = false;

  @override
  void initState() {
    super.initState();
    final r = context.session.lastPortalRole;
    _role = r == Role.admin ? Role.client : r;
  }

  void _setRole(Role r) {
    setState(() => _role = r);
    context.session.setPortalRole(r);
  }

  void _openAdmin() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AdminSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final accent = roleColor(_role);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.9, -0.9),
            radius: 1.2,
            colors: [fade(Kv.brand, kv.isDark ? 0.14 : 0.07), kv.bg],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: [
              KvCard(
                radius: 30,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: GestureDetector(onLongPress: _openAdmin, child: const KvLogo(size: 88)),
                  ),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('RWANDA OFFICIAL PLATFORM',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 1, color: kv.muted)),
                    const SizedBox(width: 8),
                    const Pill('Kigali', color: Kv.brandLight),
                  ]),
                  const SizedBox(height: 6),
                  Text('Company-verified on-demand service dispatch',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kv.muted)),
                  const SizedBox(height: 20),
                  _Segmented(
                    items: const [
                      (Icons.person_outline_rounded, 'Client'),
                      (Icons.badge_outlined, 'Worker'),
                      (Icons.apartment_rounded, 'Company'),
                    ],
                    index: _role.index,
                    colors: const [Kv.emerald, Kv.amber, Kv.blue],
                    onChanged: (i) => _setRole(Role.values[i]),
                  ),
                  const SizedBox(height: 14),
                  _Toggle(
                    signUp: _signUp,
                    accent: accent,
                    onChanged: (v) => setState(() => _signUp = v),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey('${_role.name}-$_signUp'),
                      child: _signUp ? _SignUpForm(role: _role) : _SignInForm(role: _role),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              Text('© ${DateTime.now().year} KoraVuba Rwanda • On-Demand Company-Verified Services',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kv.faint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.items, required this.index, required this.colors, required this.onChanged});
  final List<(IconData, String)> items;
  final int index;
  final List<Color> colors;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: kv.isDark ? Kv.s950 : Kv.s100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kv.border),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: i == index ? colors[i] : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(children: [
                  Icon(items[i].$1, size: 19, color: i == index ? (colors[i] == Kv.blue ? Colors.white : Kv.s950) : kv.muted),
                  const SizedBox(height: 4),
                  Text(items[i].$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: i == index ? (colors[i] == Kv.blue ? Colors.white : Kv.s950) : kv.muted,
                      )),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.signUp, required this.accent, required this.onChanged});
  final bool signUp;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    Widget item(bool value, IconData icon, String label) {
      final sel = signUp == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: sel ? (kv.isDark ? Kv.s800 : Colors.white) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: sel ? accent : kv.muted),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: sel ? kv.text : kv.muted)),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: kv.isDark ? Kv.s950 : Kv.s100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kv.border),
      ),
      child: Row(children: [
        item(false, Icons.login_rounded, 'Sign In'),
        item(true, Icons.person_add_alt_1_rounded, 'Create Account'),
      ]),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kv.isDark ? Kv.s950 : Kv.s50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kv.border),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: kv.text, height: 1.35))),
      ]),
    );
  }
}

// ======================================================================= sign in
class _SignInForm extends StatefulWidget {
  const _SignInForm({required this.role});
  final Role role;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = 'Fill in both fields.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = switch (widget.role) {
        Role.client => await AuthRepo.loginClient(_id.text, _pw.text),
        Role.worker => await AuthRepo.loginWorker(_id.text, _pw.text),
        Role.company => await AuthRepo.loginCompany(_id.text, _pw.text),
        Role.admin => await AuthRepo.loginAdmin(_id.text, _pw.text),
      };
      if (!mounted) return;
      await context.session.signIn(res);
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forgot password?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text(switch (widget.role) {
          Role.worker => 'Ask your company supervisor to reset your badge PIN, or call KoraVuba support on +250 788 000 001.',
          Role.company => 'Contact KoraVuba HQ on +250 788 000 001 or hq@koravuba.rw to verify your company and reset access.',
          _ => 'Call KoraVuba support on +250 788 000 001. In this offline version passwords can be changed from Profile once signed in.',
        }),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleColor(widget.role);
    final (idLabel, idHint, idIcon) = switch (widget.role) {
      Role.worker => ('Badge ID, phone or e-mail:', 'KV-CLEAN-00000', Icons.key_rounded),
      Role.company => ('Company e-mail or phone:', 'support@company.rw', Icons.alternate_email_rounded),
      _ => ('Mobile / MoMo Phone Number:', '+250 788 000 000', Icons.phone_outlined),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _InfoBox(
        icon: switch (widget.role) {
          Role.worker => Icons.auto_awesome_rounded,
          Role.company => Icons.apartment_rounded,
          _ => Icons.check_circle_outline_rounded,
        },
        color: accent,
        text: switch (widget.role) {
          Role.worker => 'Worker App: Enter your Provider Badge ID & password to sign in.',
          Role.company => 'Company Portal: manage your verified workers, dispatches and payouts.',
          _ => 'Client Sign In: Book verified Kigali cleaners, drivers, plumbers & nannies.',
        },
      ),
      const SizedBox(height: 16),
      KvField(
        label: idLabel,
        controller: _id,
        hint: idHint,
        icon: idIcon,
        mono: true,
        accent: accent,
        keyboard: widget.role == Role.client ? TextInputType.phone : TextInputType.text,
        textCapitalization: widget.role == Role.worker ? TextCapitalization.characters : TextCapitalization.none,
      ),
      const SizedBox(height: 14),
      KvField(
        label: widget.role == Role.worker ? 'Worker Password / Security PIN:' : 'Password / Security PIN:',
        controller: _pw,
        icon: Icons.lock_outline_rounded,
        obscure: _obscure,
        accent: accent,
        trailingLabel: GestureDetector(
          onTap: _forgot,
          child: Text('Forgot password?',
              style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationColor: accent)),
        ),
        suffix: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: fade(Kv.red, 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: fade(Kv.red, 0.4))),
          child: Text(_error!, style: const TextStyle(color: Kv.red, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
      const SizedBox(height: 18),
      KvButton(
        label: switch (widget.role) {
          Role.worker => 'Verify Badge & Password to Sign In',
          Role.company => 'Sign in to Company Portal',
          _ => 'Sign in to Client Dashboard',
        },
        icon: Icons.arrow_forward_rounded,
        color: accent,
        loading: _busy,
        onPressed: _submit,
      ),
    ]);
  }
}

// ======================================================================= sign up
class _SignUpForm extends StatefulWidget {
  const _SignUpForm({required this.role});
  final Role role;

  @override
  State<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<_SignUpForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _company = TextEditingController();
  final _nid = TextEditingController();
  final _tin = TextEditingController();
  final _rdb = TextEditingController();
  final _payout = TextEditingController();
  final _admin = TextEditingController();
  Sector _sector = kigaliSectors.first;
  List<Category> _cats = [];
  Category? _cat;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    CatalogRepo.categories().then((c) {
      if (mounted) {
        setState(() {
          _cats = c;
          _cat = c.isEmpty ? null : c.first;
        });
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _pw, _pw2, _company, _nid, _tin, _rdb, _payout, _admin]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
  String? _phoneV(String? v) => Fmt.phoneKey(v).length != 9 ? 'Enter a valid Rwanda phone number' : null;
  String? _emailV(String? v, {bool optional = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return optional ? null : 'Required';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Enter a valid e-mail';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      switch (widget.role) {
        case Role.client:
        case Role.admin:
          final res = await AuthRepo.registerClient(
              fullName: _name.text, phone: _phone.text, email: _email.text, password: _pw.text, sector: _sector);
          if (!mounted) return;
          await context.session.signIn(res);
        case Role.worker:
          if (_cat == null) throw AuthError('KoraVuba HQ has not added any service categories yet. Ask HQ to add one first.');
          final badge = await AuthRepo.registerWorker(
            companyCode: _company.text,
            fullName: _name.text,
            phone: _phone.text,
            nationalId: _nid.text,
            category: _cat!,
            password: _pw.text,
            sector: _sector,
          );
          if (!mounted) return;
          await _done('Application sent 🎉',
              'Your badge ID is $badge.\n\nYour company must approve your application before you can sign in. Keep this badge ID — it is your login.');
        case Role.company:
          await AuthRepo.registerCompany(
            businessName: _name.text,
            tin: _tin.text,
            rdb: _rdb.text,
            email: _email.text,
            phone: _phone.text,
            sector: _sector,
            payoutAccount: _payout.text,
            adminName: _admin.text,
            password: _pw.text,
          );
          if (!mounted) return;
          await _done('Registration submitted',
              'KoraVuba HQ will verify your TIN and RDB certificate. Once approved you receive your Company ID (KV-COMP-…) and can sign in with ${_email.text.trim()}.');
      }
    } on AuthError catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not create the account: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    for (final c in [_name, _phone, _email, _pw, _pw2, _company, _nid, _tin, _rdb, _payout, _admin]) {
      c.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleColor(widget.role);
    const gap = SizedBox(height: 13);
    final pwField = KvField(
      label: 'Create Password / PIN:',
      controller: _pw,
      icon: Icons.lock_outline_rounded,
      obscure: _obscure,
      accent: accent,
      validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
      suffix: IconButton(
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      ),
    );
    final pw2Field = KvField(
      label: 'Confirm Password / PIN:',
      controller: _pw2,
      icon: Icons.lock_reset_rounded,
      obscure: _obscure,
      accent: accent,
      validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
    );
    final sectorField = _Dropdown<Sector>(
      label: 'Kigali Sector:',
      value: _sector,
      items: kigaliSectors,
      text: (s) => s.label,
      onChanged: (s) => setState(() => _sector = s),
    );

    final fields = <Widget>[
      if (widget.role == Role.worker) ...[
        KvField(
          label: 'Company ID (from your employer):',
          controller: _company,
          hint: 'KV-COMP-101',
          icon: Icons.apartment_rounded,
          mono: true,
          accent: accent,
          textCapitalization: TextCapitalization.characters,
          validator: _req,
        ),
        gap,
      ],
      KvField(
        label: widget.role == Role.company ? 'Registered Business Name:' : 'Full Name:',
        controller: _name,
        icon: widget.role == Role.company ? Icons.business_rounded : Icons.person_outline_rounded,
        accent: accent,
        textCapitalization: TextCapitalization.words,
        validator: _req,
      ),
      gap,
      if (widget.role == Role.company) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: KvField(label: 'TIN Number:', controller: _tin, hint: 'TIN-1098…', mono: true, accent: accent, validator: _req)),
          const SizedBox(width: 10),
          Expanded(child: KvField(label: 'RDB Reg. No:', controller: _rdb, hint: 'RDB-2025-…', mono: true, accent: accent, validator: _req)),
        ]),
        gap,
      ],
      KvField(
        label: widget.role == Role.company ? 'Official Phone:' : 'Mobile / MoMo Phone Number:',
        controller: _phone,
        hint: '+250 788 000 000',
        icon: Icons.phone_outlined,
        keyboard: TextInputType.phone,
        accent: accent,
        validator: _phoneV,
      ),
      gap,
      if (widget.role != Role.worker) ...[
        KvField(
          label: widget.role == Role.company ? 'Official E-mail (your login):' : 'E-mail (optional):',
          controller: _email,
          icon: Icons.alternate_email_rounded,
          keyboard: TextInputType.emailAddress,
          accent: accent,
          validator: (v) => _emailV(v, optional: widget.role != Role.company),
        ),
        gap,
      ],
      if (widget.role == Role.worker) ...[
        KvField(
          label: 'National ID Number:',
          controller: _nid,
          hint: '1 1990 8 0012345 0 12',
          icon: Icons.credit_card_rounded,
          keyboard: TextInputType.number,
          mono: true,
          accent: accent,
          validator: (v) => Fmt.digits(v).length != 16 ? 'National ID has 16 digits' : null,
        ),
        gap,
        if (_cats.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: fade(Kv.amber, 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: fade(Kv.amber, 0.4))),
            child: const Text('No service categories yet. KoraVuba HQ must add categories (Control → Service categories) before workers can register.',
                style: TextStyle(color: Kv.amberLight, fontSize: 12.5)),
          ),
          gap,
        ],
        if (_cats.isNotEmpty) ...[
          _Dropdown<Category>(
            label: 'Service Category:',
            value: _cat ?? _cats.first,
            items: _cats,
            text: (c) => c.name,
            onChanged: (c) => setState(() => _cat = c),
          ),
          gap,
        ],
      ],
      sectorField,
      gap,
      if (widget.role == Role.company) ...[
        KvField(
          label: 'Payout Account (Bank / MoMo):',
          controller: _payout,
          hint: 'Bank of Kigali • 000123456-78',
          icon: Icons.account_balance_rounded,
          accent: accent,
          validator: _req,
        ),
        gap,
        KvField(
          label: 'Admin Full Name:',
          controller: _admin,
          icon: Icons.person_outline_rounded,
          accent: accent,
          textCapitalization: TextCapitalization.words,
          validator: _req,
        ),
        gap,
      ],
      pwField,
      gap,
      pw2Field,
      const SizedBox(height: 18),
      KvButton(
        label: switch (widget.role) {
          Role.worker => 'Submit Worker Application',
          Role.company => 'Register Company for Verification',
          _ => 'Create Client Account',
        },
        icon: Icons.arrow_forward_rounded,
        color: accent,
        loading: _busy,
        onPressed: _submit,
      ),
    ];

    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _InfoBox(
          icon: Icons.verified_user_outlined,
          color: accent,
          text: switch (widget.role) {
            Role.worker => 'Workers join through a registered company. Your company approves your badge before your first dispatch.',
            Role.company => 'Companies are verified by KoraVuba HQ (TIN + RDB). You then receive a Company ID for your workers.',
            _ => 'Create your free client account to book company-verified services across Kigali.',
          },
        ),
        const SizedBox(height: 16),
        ...fields,
      ]),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.text, required this.onChanged});
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kv.text)),
      const SizedBox(height: 7),
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: kv.card,
        borderRadius: BorderRadius.circular(14),
        items: [for (final i in items) DropdownMenuItem<T>(value: i, child: Text(text(i), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ]);
  }
}

// ======================================================================= admin
class _AdminSheet extends StatefulWidget {
  const _AdminSheet();

  @override
  State<_AdminSheet> createState() => _AdminSheetState();
}

class _AdminSheetState extends State<_AdminSheet> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_id.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = 'Enter the admin e-mail and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await AuthRepo.loginAdmin(_id.text.trim(), _pw.text);
      if (!mounted) return;
      final session = context.session;
      Navigator.pop(context);
      await session.signIn(res);
      return;
    } on AuthError catch (e) {
      if (mounted) {
        setState(() => _error = e.message.startsWith('Incorrect')
            ? '${e.message}\nIf you just updated the app, uninstall the old version first: the phone keeps its old database.'
            : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign in failed: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('KoraVuba Executive HQ',
            icon: Icons.admin_panel_settings_rounded, color: Kv.purple, subtitle: 'Platform administrators only.'),
        const SizedBox(height: 14),
        KvField(label: 'Admin e-mail or phone:', controller: _id, icon: Icons.alternate_email_rounded, accent: Kv.purple),
        const SizedBox(height: 12),
        KvField(
          label: 'Password:',
          controller: _pw,
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          accent: Kv.purple,
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: fade(Kv.red, 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: fade(Kv.red, 0.4))),
            child: Text(_error!, style: const TextStyle(color: Kv.red, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 18),
        KvButton(label: 'Enter HQ', icon: Icons.shield_rounded, color: Kv.purple, loading: _busy, onPressed: _go),
      ]),
    );
  }
}
