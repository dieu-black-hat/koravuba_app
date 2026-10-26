import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/chat_repo.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'call.dart';

/// Conversation list for clients and workers.
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key, required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final userId = s.user!.id;
    final profileId = s.profileId;
    final kv = context.kv;
    return DataView<List<Conversation>>(
      load: () => ChatRepo.list(userId: userId, providerProfileId: profileId),
      builder: (context, list, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            KvCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle(
                  profileId == null ? 'Direct Chat with Mapped & Radar Providers' : 'Client Dispatch Chat',
                  icon: Icons.chat_bubble_outline_rounded,
                  color: accent,
                  subtitle: profileId == null
                      ? 'Chat directly with the company-verified providers you booked.'
                      : 'Talk to clients about directions, timing and job details.',
                  trailing: MonoTag('LIVE', color: accent, size: 9.5),
                ),
                const SizedBox(height: 12),
                MonoTag('${list.length} conversation${list.length == 1 ? '' : 's'}', color: accent, icon: Icons.circle),
              ]),
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const EmptyState(
                icon: Icons.forum_outlined,
                title: 'No conversations yet',
                message: 'A chat opens automatically with every booking.',
              ),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KvCard(
                  padding: const EdgeInsets.all(14),
                  radius: 20,
                  onTap: () => push(context, ChatScreen(conversation: c, accent: accent)),
                  child: Row(children: [
                    Avatar(name: c.otherName, path: c.otherPhoto, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(c.otherName,
                                overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
                          ),
                          Text(Fmt.ago(c.lastAt), style: TextStyle(fontSize: 11, color: kv.faint)),
                        ]),
                        if (c.subtitle.isNotEmpty)
                          Text(c.subtitle, style: TextStyle(fontSize: 11, fontFamily: Kv.mono, color: accent)),
                        const SizedBox(height: 3),
                        Row(children: [
                          Expanded(
                            child: Text(c.lastMessage.isEmpty ? 'Say hello 👋' : c.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: c.unread > 0 ? kv.text : kv.muted)),
                          ),
                          if (c.unread > 0) Pill('${c.unread}', color: Kv.red, solid: true),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversation, required this.accent});
  final Conversation conversation;
  final Color accent;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<Message> _messages = [];
  Timer? _timer;
  late final String _me;

  @override
  void initState() {
    super.initState();
    _me = context.session.user!.id;
    _load(scroll: true);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool scroll = false}) async {
    final list = await ChatRepo.messages(widget.conversation.id);
    await ChatRepo.markRead(widget.conversation.id, _me);
    if (!mounted) return;
    final grew = list.length != _messages.length;
    setState(() => _messages = list);
    if (scroll || grew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await ChatRepo.send(widget.conversation.id, _me, t);
    await _load(scroll: true);
    if (mounted) context.session.changed();
  }

  Future<void> _delete(Message m) async {
    if (m.senderId != _me || m.type != 'text') return;
    if (!await confirm(context, 'Delete message?', m.content, ok: 'Delete', danger: true)) return;
    await ChatRepo.deleteMessage(m.id, _me);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final c = widget.conversation;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Avatar(name: c.otherName, path: c.otherPhoto, size: 36, color: widget.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.otherName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              if (c.subtitle.isNotEmpty)
                Text(c.subtitle, style: TextStyle(fontSize: 11, fontFamily: Kv.mono, color: widget.accent)),
            ]),
          ),
        ]),
        actions: [
          if (c.otherPhone.isNotEmpty) IconButton(onPressed: () => callPhone(context, c.otherPhone), icon: const Icon(Icons.call_rounded)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Text('No messages yet. Say hello 👋', style: TextStyle(color: kv.muted)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    if (m.type != 'text') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(color: kv.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: kv.border)),
                            child: Text(m.content, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kv.muted)),
                          ),
                        ),
                      );
                    }
                    final mine = m.senderId == _me;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _delete(m),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: mine ? widget.accent : kv.card,
                            border: mine ? null : Border.all(color: kv.border),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(mine ? 18 : 4),
                              bottomRight: Radius.circular(mine ? 4 : 18),
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(m.content,
                                style: TextStyle(color: mine ? (widget.accent == Kv.blue ? Colors.white : Kv.s950) : kv.text, fontSize: 14.5)),
                            const SizedBox(height: 3),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(Fmt.time(m.createdAt),
                                  style: TextStyle(fontSize: 10, color: mine ? fade(Kv.s950, 0.6) : kv.faint)),
                              if (mine) ...[
                                const SizedBox(width: 4),
                                Icon(m.isRead ? Icons.done_all_rounded : Icons.done_rounded, size: 13, color: fade(Kv.s950, 0.6)),
                              ],
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Type a message…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: widget.accent, minimumSize: const Size(50, 50)),
                onPressed: _send,
                icon: Icon(Icons.send_rounded, color: widget.accent == Kv.blue ? Colors.white : Kv.s950),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
