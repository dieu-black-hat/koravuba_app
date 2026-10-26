import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koravuba/core/django_password.dart';
import 'package:koravuba/core/format.dart';
import 'package:koravuba/core/geo.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Django pbkdf2_sha256', () {
    test('RFC test vectors', () {
      expect(hex(DjangoPassword.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 1)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(hex(DjangoPassword.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 4096)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('make + verify round trip', () {
      final h = DjangoPassword.makeSync('123456', iterations: 1000);
      expect(h.startsWith('pbkdf2_sha256\$1000\$'), isTrue);
      expect(DjangoPassword.verifySync('123456', h), isTrue);
      expect(DjangoPassword.verifySync('1234567', h), isFalse);
    });

    test('verifies a hash produced by Django / Python', () {
      // python: hashlib.pbkdf2_hmac('sha256', b'123456', b'abcdefghijklmnopqrstuv', 1000)
      const h = 'pbkdf2_sha256\$1000\$abcdefghijklmnopqrstuv\$PY_HASH';
      expect(DjangoPassword.verifySync('123456', h.replaceFirst('PY_HASH', _pyHash)), isTrue);
    });
  });

  test('formatting', () {
    expect(Fmt.money(25000), '25,000 RWF');
    expect(Fmt.phone('0788123456'), '+250 788 123 456');
    expect(Fmt.phoneKey('+250 788 123 456'), Fmt.phoneKey('0788123456'));
    expect(Fmt.initials('Diane Kanimba'), 'DK');
  });

  test('distance', () {
    final d = distanceKm(-1.9536, 30.1131, -1.9420, 30.1250);
    expect(d > 1.5 && d < 2.0, isTrue);
  });
}

const _pyHash = 'bJ9W1ZSqJuwENFncQSZypQwHGD5xwaXQW4YqECsTsKI=';
