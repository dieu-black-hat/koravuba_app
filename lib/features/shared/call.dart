import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/common.dart';

Future<void> callPhone(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
  try {
    if (!await launchUrl(uri)) {
      if (context.mounted) showSnack(context, 'Could not open the dialer for $phone', error: true);
    }
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not open the dialer for $phone', error: true);
  }
}
