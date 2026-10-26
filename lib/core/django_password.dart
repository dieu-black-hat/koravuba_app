import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

/// Django-compatible password hashing (`pbkdf2_sha256$<iterations>$<salt>$<hash>`).
///
/// The users copied from your MySQL database keep their real passwords: the
/// app checks them exactly like Django does. Hashes created in the app can be
/// read by Django too, so accounts keep working once the app syncs with the
/// web platform.
class DjangoPassword {
  DjangoPassword._();

  /// Iterations for new hashes. Django accepts any count (it re-hashes with its
  /// own default on the next web login), so a phone-friendly value is used.
  static const int defaultIterations = 100000;

  static Future<bool> verify(String password, String encoded) =>
      compute(_verifyEntry, <String>[password, encoded]);

  static Future<String> make(String password, {int iterations = defaultIterations}) =>
      compute(_makeEntry, <String>[password, iterations.toString(), _salt()]);

  static bool verifySync(String password, String encoded) => _verifyEntry(<String>[password, encoded]);

  static String makeSync(String password, {int iterations = defaultIterations}) =>
      _makeEntry(<String>[password, iterations.toString(), _salt()]);

  static String _salt() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = math.Random.secure();
    return List.generate(22, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Raw PBKDF2-HMAC-SHA256 with a 32-byte output.
  static Uint8List pbkdf2(List<int> password, List<int> salt, int iterations) {
    if (_fastOk) return _pbkdf2Fast(password, salt, iterations);
    return _pbkdf2Slow(password, salt, iterations);
  }

  // RFC 7914 test vector: checks the fast implementation once; if it ever
  // disagrees the slower (but simple) crypto-package version is used instead.
  static final bool _fastOk = _hex(_pbkdf2Fast(utf8.encode('password'), utf8.encode('salt'), 2)) ==
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43';
}

bool _verifyEntry(List<String> a) {
  final password = a[0];
  final parts = a[1].split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;
  final dk = DjangoPassword.pbkdf2(utf8.encode(password), utf8.encode(parts[2]), iterations);
  final calc = base64.encode(dk);
  final expected = parts[3];
  if (calc.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < calc.length; i++) {
    diff |= calc.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

String _makeEntry(List<String> a) {
  final iterations = int.parse(a[1]);
  final salt = a[2];
  final dk = DjangoPassword.pbkdf2(utf8.encode(a[0]), utf8.encode(salt), iterations);
  return 'pbkdf2_sha256\$$iterations\$$salt\$${base64.encode(dk)}';
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

// ---------------------------------------------------------------- slow path
Uint8List _pbkdf2Slow(List<int> password, List<int> salt, int iterations) {
  final hmac = crypto.Hmac(crypto.sha256, password);
  var u = hmac.convert(<int>[...salt, 0, 0, 0, 1]).bytes;
  final t = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return t;
}

// ---------------------------------------------------------------- fast path
// SHA-256 with pre-computed HMAC inner/outer states: two compressions per
// iteration instead of four, ~1 s for Django's 600 000 iterations on a phone.
const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];
const List<int> _h0 = <int>[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

/// One SHA-256 compression. [w] has 64 slots; the first 16 must hold the block.
void _compress(Uint32List state, Uint32List w) {
  for (var t = 16; t < 64; t++) {
    final x = w[t - 15];
    final y = w[t - 2];
    final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >> 3);
    final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >> 10);
    w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
  }
  var a = state[0], b = state[1], c = state[2], d = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  for (var t = 0; t < 64; t++) {
    final bigS1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ ((~e) & g);
    final t1 = (h + bigS1 + ch + _k[t] + w[t]) & 0xffffffff;
    final bigS0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (bigS0 + maj) & 0xffffffff;
    h = g;
    g = f;
    f = e;
    e = (d + t1) & 0xffffffff;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & 0xffffffff;
  }
  state[0] = (state[0] + a) & 0xffffffff;
  state[1] = (state[1] + b) & 0xffffffff;
  state[2] = (state[2] + c) & 0xffffffff;
  state[3] = (state[3] + d) & 0xffffffff;
  state[4] = (state[4] + e) & 0xffffffff;
  state[5] = (state[5] + f) & 0xffffffff;
  state[6] = (state[6] + g) & 0xffffffff;
  state[7] = (state[7] + h) & 0xffffffff;
}

void _loadBlock(Uint32List w, List<int> bytes, int offset) {
  for (var i = 0; i < 16; i++) {
    final o = offset + i * 4;
    w[i] = (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
  }
}

/// Continues hashing [msg] from [mid] (which already consumed [prefixLen] bytes).
Uint32List _finish(Uint32List mid, List<int> msg, int prefixLen) {
  final total = prefixLen + msg.length;
  var padLen = 64 - ((total + 9) % 64);
  if (padLen == 64) padLen = 0;
  final buf = Uint8List(msg.length + 9 + padLen);
  buf.setAll(0, msg);
  buf[msg.length] = 0x80;
  final bits = total * 8;
  for (var i = 0; i < 8; i++) {
    buf[buf.length - 1 - i] = (bits >> (8 * i)) & 0xff;
  }
  final state = Uint32List.fromList(mid);
  final w = Uint32List(64);
  for (var off = 0; off < buf.length; off += 64) {
    _loadBlock(w, buf, off);
    _compress(state, w);
  }
  return state;
}

Uint8List _wordsToBytes(Uint32List words) {
  final out = Uint8List(words.length * 4);
  for (var i = 0; i < words.length; i++) {
    out[i * 4] = (words[i] >> 24) & 0xff;
    out[i * 4 + 1] = (words[i] >> 16) & 0xff;
    out[i * 4 + 2] = (words[i] >> 8) & 0xff;
    out[i * 4 + 3] = words[i] & 0xff;
  }
  return out;
}

Uint8List _pbkdf2Fast(List<int> password, List<int> salt, int iterations) {
  var key = password;
  if (key.length > 64) key = crypto.sha256.convert(key).bytes;
  final ipad = Uint8List(64);
  final opad = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    final k = i < key.length ? key[i] : 0;
    ipad[i] = k ^ 0x36;
    opad[i] = k ^ 0x5c;
  }
  final w = Uint32List(64);
  final istate = Uint32List.fromList(_h0);
  _loadBlock(w, ipad, 0);
  _compress(istate, w);
  final ostate = Uint32List.fromList(_h0);
  _loadBlock(w, opad, 0);
  _compress(ostate, w);

  final inner1 = _finish(istate, <int>[...salt, 0, 0, 0, 1], 64);
  final u = _finish(ostate, _wordsToBytes(inner1), 64);
  final t = Uint32List.fromList(u);
  final s = Uint32List(8);
  for (var i = 1; i < iterations; i++) {
    s.setAll(0, istate);
    for (var j = 0; j < 8; j++) {
      w[j] = u[j];
    }
    w[8] = 0x80000000;
    for (var j = 9; j < 15; j++) {
      w[j] = 0;
    }
    w[15] = 768; // (64 + 32) * 8 bits
    _compress(s, w);
    for (var j = 0; j < 8; j++) {
      w[j] = s[j];
    }
    w[8] = 0x80000000;
    for (var j = 9; j < 15; j++) {
      w[j] = 0;
    }
    w[15] = 768;
    s.setAll(0, ostate);
    _compress(s, w);
    for (var j = 0; j < 8; j++) {
      u[j] = s[j];
      t[j] ^= s[j];
    }
  }
  return _wordsToBytes(t);
}
