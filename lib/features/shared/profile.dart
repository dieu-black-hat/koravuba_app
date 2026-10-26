import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/auth_repo.dart';
import '../../widgets/common.dart';

/// Profile / account page shared by every role: photo, personal details,
/// MoMo number, sector (location), password, theme, sign out.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.accent, required this.roleTag, this.extra = const []});
  final Color accent;
  final String roleTag;
  final List<Widget> extra;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _momo = TextEditingController();
  final _bio = TextEditingController();
  String _network = 'MTN MoMo';
  Sector _sector = kigaliSectors.first;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  Future<void> _fill() async {
    final s = context.session;
    final u = s.user!;
    final st = await AuthRepo.settings(u.id);
    if (!mounted) return;
    setState(() {
      _name.text = u.fullName;
      _email.text = u.email;
      _phone.text = Fmt.phone(u.phone);
      _bio.text = u.bio.isEmpty ? 'Resident in Kigali looking for verified on-demand services.' : u.bio;
      _momo.text = Fmt.phone('${st['momo_number'] ?? u.phone}');
      _network = '${st['momo_network'] ?? 'MTN MoMo'}'.startsWith('Airtel') ? 'Airtel Money' : 'MTN MoMo';
      _sector = s.sector;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _momo, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final s = context.session;
    try {
      final parts = _name.text.trim().split(RegExp(r'\s+'));
      await AuthRepo.updateProfile(
        s.user!.id,
        first: parts.first,
        last: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        email: _email.text,
        phone: _phone.text,
        bio: _bio.text.trim(),
        sector: _sector,
      );
      await AuthRepo.saveSettings(s.user!.id, momo: '+250${Fmt.phoneKey(_momo.text)}', network: _network, sector: _sector.name);
      await s.reloadUser();
      if (mounted) showSnack(context, 'Profile saved');
    } on AuthError catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resync() async {
    final s = context.session;
    await AuthRepo.updateProfile(s.user!.id,
        first: s.user!.firstName, last: s.user!.lastName, email: s.user!.email, phone: s.user!.phone, sector: _sector);
    await s.reloadUser();
    if (mounted) showSnack(context, 'Position synced to ${_sector.label}');
  }

  Future<void> _photo() async {
    final s = context.session;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
      if (x == null) return;
      final dir = Directory(p.join(await getDatabasesPath(), 'media'));
      await dir.create(recursive: true);
      final dest = p.join(dir.path, 'profile_${s.user!.id}_${DateTime.now().millisecondsSinceEpoch}${p.extension(x.path)}');
      await File(x.path).copy(dest);
      await AuthRepo.setPhoto(s.user!.id, dest);
      await s.reloadUser();
      if (mounted) showSnack(context, 'Profile picture updated');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load the picture: $e', error: true);
    }
  }

  Future<void> _password() async {
    final old = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: old, obscureText: true, decoration: const InputDecoration(hintText: 'Current password')),
          const SizedBox(height: 10),
          TextField(controller: next, obscureText: true, decoration: const InputDecoration(hintText: 'New password (min 6)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (next.text.length < 6) {
      showSnack(context, 'New password must have at least 6 characters', error: true);
      return;
    }
    try {
      await AuthRepo.changePassword(context.session.user!.id, old.text, next.text);
      if (mounted) showSnack(context, 'Password changed');
    } on AuthError catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _signOut() async {
    if (!await confirm(context, 'Sign out?', 'You can sign in again any time.', ok: 'Sign out')) return;
    if (!mounted) return;
    final s = context.session;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await s.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final s = context.watch<Session>();
    final u = s.user;
    final accent = widget.accent;
    if (u == null) return const SizedBox.shrink();
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          KvCard(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [kv.card, fade(accent, kv.isDark ? 0.22 : 0.12)],
            ),
            borderColor: fade(accent, 0.35),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(onTap: _photo, child: Avatar(name: u.fullName, path: u.profileImage, size: 74, color: accent)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.fullName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kv.text)),
                  const SizedBox(height: 3),
                  Text('${u.email} • ${Fmt.phone(u.phone)}', style: TextStyle(fontSize: 12, color: kv.muted)),
                  if (u.bio.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('"${u.bio}"', style: TextStyle(fontSize: 12.5, color: accent, fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    MonoTag(widget.roleTag, color: accent, size: 10),
                    MonoTag('${s.sector.name} Account', color: accent, size: 10),
                  ]),
                ]),
              ),
            ]),
          ),
          ...widget.extra,
          const SizedBox(height: 14),
          KvCard(
            borderColor: fade(accent, 0.45),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('Device Location Radar',
                  icon: Icons.near_me_outlined,
                  color: accent,
                  subtitle: 'Your Kigali sector is used to show the nearest verified providers and exact distances.'),
              const SizedBox(height: 12),
              DropdownButtonFormField<Sector>(
                initialValue: _sector,
                isExpanded: true,
                dropdownColor: kv.card,
                items: [for (final x in kigaliSectors) DropdownMenuItem(value: x, child: Text(x.label))],
                onChanged: (x) => setState(() => _sector = x ?? _sector),
              ),
              const SizedBox(height: 10),
              KvButton(label: 'Re-sync Position', icon: Icons.my_location_rounded, color: accent, expand: false, height: 44, onPressed: _resync),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: kv.isDark ? Kv.s950 : Kv.s50, borderRadius: BorderRadius.circular(14), border: Border.all(color: kv.border)),
                child: Column(children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'GPS Status: ', style: TextStyle(color: kv.text, fontWeight: FontWeight.w800)),
                    TextSpan(text: 'ACTIVE & MAPPED ON RADAR', style: TextStyle(color: accent, fontWeight: FontWeight.w900)),
                  ]), style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text('Lat: ${s.location.lat.toStringAsFixed(4)}, Lng: ${s.location.lng.toStringAsFixed(4)}',
                      style: TextStyle(fontFamily: Kv.mono, fontSize: 11.5, color: kv.muted)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          KvCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('Account & Payment Details', icon: Icons.person_outline_rounded, color: accent),
              const SizedBox(height: 14),
              KvButton(label: 'Upload Profile Picture', icon: Icons.photo_camera_outlined, color: accent, expand: false, height: 42, onPressed: _photo),
              const SizedBox(height: 14),
              KvField(label: 'About Me / Bio:', controller: _bio, maxLines: 2, accent: accent),
              const SizedBox(height: 12),
              KvField(
                  label: 'Full Name:',
                  controller: _name,
                  accent: accent,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              KvField(
                label: 'Email Address:',
                controller: _email,
                keyboard: TextInputType.emailAddress,
                accent: accent,
                validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid e-mail',
              ),
              const SizedBox(height: 12),
              KvField(
                label: 'Phone Number:',
                controller: _phone,
                keyboard: TextInputType.phone,
                accent: accent,
                validator: (v) => Fmt.phoneKey(v).length == 9 ? null : 'Enter a valid phone number',
              ),
              const SizedBox(height: 12),
              KvField(label: 'MTN / Airtel MoMo Number:', controller: _momo, keyboard: TextInputType.phone, mono: true, accent: accent),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final n in const ['MTN MoMo', 'Airtel Money'])
                  ChoiceChip(label: Text(n), selected: _network == n, onSelected: (_) => setState(() => _network = n)),
              ]),
              const SizedBox(height: 16),
              KvButton(label: 'Save changes', icon: Icons.save_rounded, color: accent, loading: _saving, onPressed: _save),
            ]),
          ),
          const SizedBox(height: 14),
          KvCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              ListTile(
                leading: Icon(Icons.lock_reset_rounded, color: accent),
                title: const Text('Change password', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _password,
              ),
              ListTile(
                leading: Icon(kv.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: accent),
                title: Text(kv.isDark ? 'Switch to light mode' : 'Switch to dark mode', style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => s.toggleTheme(),
              ),
              ListTile(
                leading: Icon(Icons.storage_rounded, color: accent),
                title: const Text('Offline database', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('All data is stored on this phone (copy of globalconnect_db).'),
                onTap: () async {
                  final path = await AppDb.path();
                  if (context.mounted) showSnack(context, path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Kv.red),
                title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w700, color: Kv.red)),
                onTap: _signOut,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
