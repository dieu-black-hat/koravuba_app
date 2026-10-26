import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/chat_repo.dart';
import '../../data/notify.dart';
import '../../widgets/common.dart';
import '../../widgets/role_shell.dart';
import '../shared/booking_detail.dart';
import '../shared/messages.dart';
import '../shared/notifications.dart';
import '../shared/profile.dart';
import 'activities.dart';
import 'client_home.dart';

class ClientShell extends StatelessWidget {
  const ClientShell({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = context.session.user!.id;
    return RoleShell(
      accent: Kv.emerald,
      roleLabel: 'CLIENT',
      tabs: [
        const ShellTab(icon: Icons.home_outlined, label: 'Home', page: ClientHome()),
        ShellTab(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          page: const MessagesPage(accent: Kv.emerald),
          badge: () => ChatRepo.unreadTotal(userId: userId),
        ),
        ShellTab(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          page: const NotificationsPage(accent: Kv.emerald),
          badge: () => Notify.unread(userId),
        ),
        const ShellTab(icon: Icons.history_rounded, label: 'Activities', page: ActivitiesPage(viewer: Viewer.client)),
        const ShellTab(
          icon: Icons.person_outline_rounded,
          label: 'Profile',
          page: ProfilePage(accent: Kv.emerald, roleTag: 'CLIENT VERIFIED'),
        ),
      ],
    );
  }
}
