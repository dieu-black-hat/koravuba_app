import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_repo.dart';
import '../data/models.dart';
import 'geo.dart';

/// Signed-in user, role, theme and the client's location.
class Session extends ChangeNotifier {
  Session(this._prefs);

  final SharedPreferences _prefs;

  AppUser? user;
  Role? role;
  String? profileId; // worker: provider_profiles.id
  String? entityId; // company admin / worker: entities.id
  bool ready = false;

  /// Bumped after any write so open screens can reload their data.
  int revision = 0;

  ThemeMode get themeMode => (_prefs.getBool('dark') ?? true) ? ThemeMode.dark : ThemeMode.light;
  bool get isDark => themeMode == ThemeMode.dark;

  Future<void> toggleTheme() async {
    await _prefs.setBool('dark', !isDark);
    notifyListeners();
  }

  bool get signedIn => user != null && role != null;

  Role get lastPortalRole => Role.values.firstWhere((r) => r.name == _prefs.getString('portal'), orElse: () => Role.client);
  Future<void> setPortalRole(Role r) => _prefs.setString('portal', r.name);

  double get radiusKm => _prefs.getDouble('radius') ?? 5;
  Future<void> setRadius(double v) async {
    await _prefs.setDouble('radius', v);
    notifyListeners();
  }

  LatLng get location {
    final lat = user?.lat;
    final lng = user?.lng;
    if (lat != null && lng != null && lat < -1.85 && lat > -2.1 && lng > 29.95 && lng < 30.25) return LatLng(lat, lng);
    return sectorByName(user?.address).point;
  }

  Sector get sector {
    final l = location;
    return nearestSector(l.lat, l.lng);
  }

  Future<void> restore() async {
    final id = _prefs.getString('user_id');
    final r = Role.values.where((e) => e.name == _prefs.getString('role')).firstOrNull;
    if (id != null && r != null) {
      final res = await AuthRepo.restore(id, r);
      if (res != null) _apply(res);
    }
    ready = true;
    notifyListeners();
  }

  Future<void> signIn(AuthResult res) async {
    _apply(res);
    await _prefs.setString('user_id', res.user.id);
    await _prefs.setString('role', res.role.name);
    notifyListeners();
  }

  void _apply(AuthResult res) {
    user = res.user;
    role = res.role;
    profileId = res.profileId;
    entityId = res.entityId;
  }

  Future<void> reloadUser() async {
    final id = user?.id;
    if (id == null) return;
    user = await AuthRepo.userById(id) ?? user;
    changed();
  }

  void changed() {
    revision++;
    notifyListeners();
  }

  Future<void> signOut() async {
    user = null;
    role = null;
    profileId = null;
    entityId = null;
    await _prefs.remove('user_id');
    await _prefs.remove('role');
    notifyListeners();
  }
}
